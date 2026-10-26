#ifdef __SWITCH__

// Avoid pulling in Ruby's assert.h from libnx service.h (see switch_main.cpp)
#define RUBY_ASSERT_H 1

#include <switch.h>
#include <SDL.h>
#include <SDL_image.h>
#include <SDL_ttf.h>

#include <dirent.h>
#include <math.h>
#include <stdio.h>
#include <string.h>
#include <strings.h>
#include <time.h>

#include <algorithm>

#include "switch_pickerui.h"

// Draws a Switch home-screen look-alike with SDL_ttf/SDL_image onto a plain
// surface and copies it into a libnx framebuffer, so SDL video stays
// untouched until mkxp-z initializes it.

namespace {

const int SCREEN_W = 1280, SCREEN_H = 720;
const int TILE = 256, TILE_GAP = 16, TILE_RADIUS = 6;
const int ROW_X = 96, TILE_Y = 210;
const int VISIBLE_TILES = (SCREEN_W - ROW_X) / (TILE + TILE_GAP);
const int FOOTER_Y = 646;

struct Rgb { Uint8 r, g, b; };
const Rgb BG = {45, 45, 45};
const Rgb TEXT = {255, 255, 255};
const Rgb TEXT_DIM = {170, 170, 170};
const Rgb LINE = {90, 90, 90};
const Rgb TILE_BG = {70, 70, 70};
const Rgb ACCENT = {0, 195, 227};
const Rgb ACCENT_HI = {130, 235, 250};

struct Fonts {
    TTF_Font *small = NULL, *medium = NULL, *title = NULL, *initials = NULL;
};

Uint32 mapRgb(SDL_Surface *s, Rgb c) {
    return SDL_MapRGBA(s->format, c.r, c.g, c.b, 255);
}

Rgb lerp(Rgb a, Rgb b, double t) {
    return {(Uint8)(a.r + (b.r - a.r) * t), (Uint8)(a.g + (b.g - a.g) * t),
            (Uint8)(a.b + (b.b - a.b) * t)};
}

// How far row y of an h-tall rounded rect is inset by its corners
int cornerInset(int y, int h, int rad) {
    int dy = 0;
    if (y < rad)
        dy = rad - y;
    else if (y >= h - rad)
        dy = y - (h - rad) + 1;
    if (dy <= 0)
        return 0;
    double d = dy - 0.5;
    return (int)(rad - sqrt((double)rad * rad - d * d) + 0.5);
}

void fillRoundRect(SDL_Surface *s, SDL_Rect r, int rad, Uint32 color) {
    for (int y = 0; y < r.h; ++y) {
        int inset = cornerInset(y, r.h, rad);
        SDL_Rect row = {r.x + inset, r.y + y, r.w - 2 * inset, 1};
        SDL_FillRect(s, &row, color);
    }
}

// Makes the corners of a 32-bit surface with alpha transparent
void roundCorners(SDL_Surface *s, int rad) {
    SDL_LockSurface(s);
    for (int y = 0; y < s->h; ++y) {
        int inset = cornerInset(y, s->h, rad);
        Uint32 *row = (Uint32 *)((Uint8 *)s->pixels + y * s->pitch);
        for (int x = 0; x < inset; ++x)
            row[x] = row[s->w - 1 - x] = 0;
    }
    SDL_UnlockSurface(s);
}

// Shortens s with "..." until it fits in maxW pixels
std::string fitText(TTF_Font *f, std::string s, int maxW) {
    int w = 0;
    if (TTF_SizeUTF8(f, s.c_str(), &w, NULL) != 0 || w <= maxW)
        return s;
    while (!s.empty()) {
        do
            s.pop_back(); // drop a whole UTF-8 sequence
        while (!s.empty() && ((unsigned char)s.back() & 0xC0) == 0x80);
        if (!s.empty())
            s.pop_back();
        std::string t = s + "...";
        if (TTF_SizeUTF8(f, t.c_str(), &w, NULL) == 0 && w <= maxW)
            return t;
    }
    return s;
}

enum Align { LEFT, CENTER, RIGHT };

// Returns the drawn width, 0 if nothing could be rendered
int drawText(SDL_Surface *dst, TTF_Font *f, const std::string &s, Rgb c,
             int x, int y, Align align) {
    SDL_Color col = {c.r, c.g, c.b, 255};
    SDL_Surface *t = TTF_RenderUTF8_Blended(f, s.c_str(), col);
    if (!t)
        return 0;
    SDL_Rect r = {x - (align == CENTER ? t->w / 2 : align == RIGHT ? t->w : 0), y, t->w, t->h};
    SDL_BlitSurface(t, NULL, dst, &r);
    int w = t->w;
    SDL_FreeSurface(t);
    return w;
}

// ---- Thumbnails ----

// <dir>/<base>.<image ext>, any capitalization, or ""
std::string findImage(const std::string &dir, const std::string &base) {
    static const char *exts[] = {"png", "jpg", "jpeg", "bmp", NULL};
    DIR *d = opendir(dir.c_str());
    if (!d)
        return "";
    std::string found;
    while (struct dirent *e = readdir(d)) {
        const char *n = e->d_name;
        if (strncasecmp(n, base.c_str(), base.size()) != 0 || n[base.size()] != '.')
            continue;
        for (const char **ext = exts; *ext && found.empty(); ++ext)
            if (strcasecmp(n + base.size() + 1, *ext) == 0)
                found = dir + "/" + n;
        if (!found.empty())
            break;
    }
    closedir(d);
    return found;
}

// Ruby Marshal integer at p (lengths only), or -1
long marshalInt(const std::string &d, size_t &p) {
    if (p >= d.size())
        return -1;
    signed char c = d[p++];
    if (c == 0)
        return 0;
    if (c > 4)
        return c - 5;
    if (c < 0)
        return -1;
    long n = 0;
    for (int i = 0; i < c && p < d.size(); ++i)
        n |= (long)(unsigned char)d[p++] << (8 * i);
    return n;
}

// Title screen image name from Data/System: @title_name (XP) or
// @title1_name (VX Ace), a Marshal String optionally wrapped in 'I'.
std::string systemTitleName(const std::string &dir) {
    static const char *files[] = {"Data/System.rxdata", "Data/System.rvdata",
                                  "Data/System.rvdata2", NULL};
    for (const char **file = files; *file; ++file) {
        FILE *f = fopen((dir + "/" + *file).c_str(), "rb");
        if (!f)
            continue;
        std::string data;
        char buf[4096];
        size_t n;
        while ((n = fread(buf, 1, sizeof(buf), f)) > 0 && data.size() < (4 << 20))
            data.append(buf, n);
        fclose(f);

        for (const char *key : {"@title1_name", "@title_name"}) {
            size_t p = data.find(key);
            if (p == std::string::npos)
                continue;
            p += strlen(key);
            if (p < data.size() && data[p] == 'I')
                ++p;
            if (p >= data.size() || data[p++] != '"')
                continue;
            long len = marshalInt(data, p);
            if (len > 0 && p + len <= data.size())
                return data.substr(p, len);
        }
    }
    return "";
}

// cover/icon/thumbnail image in the game folder, else the title screen
std::string findThumbnail(const std::string &dir) {
    for (const char *base : {"cover", "icon", "thumbnail"}) {
        std::string f = findImage(dir, base);
        if (!f.empty())
            return f;
    }
    static const char *titleDirs[] = {"Graphics/Titles", "Graphics/Titles1", NULL};
    std::string sysName = systemTitleName(dir);
    for (const std::string &name : {std::string("title"), sysName}) {
        if (name.empty())
            continue;
        for (const char **td = titleDirs; *td; ++td) {
            std::string f = findImage(dir + "/" + *td, name);
            if (!f.empty())
                return f;
        }
    }
    return "";
}

std::string initialsOf(const std::string &name) {
    std::string out;
    bool wordStart = true;
    for (char c : name) {
        if (c == ' ' || c == '_' || c == '-') {
            wordStart = true;
        } else if (wordStart && isalnum((unsigned char)c) && out.size() < 2) {
            out += (char)toupper((unsigned char)c);
            wordStart = false;
        } else {
            wordStart = false;
        }
    }
    return out.empty() ? "?" : out;
}

SDL_Surface *makeThumb(const PickerGame &g, const Fonts &fonts) {
    SDL_Surface *t = SDL_CreateRGBSurfaceWithFormat(0, TILE, TILE, 32, SDL_PIXELFORMAT_RGBA32);
    if (!t)
        return NULL;

    std::string path = findThumbnail(g.dir);
    SDL_Surface *img = path.empty() ? NULL : IMG_Load(path.c_str());
    if (img) {
        SDL_Surface *conv = SDL_ConvertSurfaceFormat(img, SDL_PIXELFORMAT_RGBA32, 0);
        SDL_FreeSurface(img);
        SDL_FillRect(t, NULL, mapRgb(t, TILE_BG));
        if (conv) {
            // Fill the square tile with the image's center
            int side = std::min(conv->w, conv->h);
            SDL_Rect src = {(conv->w - side) / 2, (conv->h - side) / 2, side, side};
            SDL_SetSurfaceBlendMode(conv, SDL_BLENDMODE_BLEND);
            SDL_BlitScaled(conv, &src, t, NULL);
            SDL_FreeSurface(conv);
        }
    } else {
        unsigned h = 5381;
        for (char c : g.name)
            h = h * 33 + (unsigned char)c;
        Rgb c = {(Uint8)(60 + h % 110), (Uint8)(60 + (h >> 8) % 110), (Uint8)(60 + (h >> 16) % 110)};
        SDL_FillRect(t, NULL, mapRgb(t, c));
        drawText(t, fonts.initials, initialsOf(g.name), TEXT, TILE / 2,
                 (TILE - TTF_FontHeight(fonts.initials)) / 2, CENTER);
    }
    roundCorners(t, TILE_RADIUS);
    return t;
}

// ---- Frame ----

void drawButtonGlyph(SDL_Surface *c, TTF_Font *f, const char *label, int cx, int cy) {
    const int r = 14;
    fillRoundRect(c, {cx - r, cy - r, 2 * r, 2 * r}, r, mapRgb(c, TEXT));
    drawText(c, f, label, BG, cx, cy - TTF_FontHeight(f) / 2, CENTER);
}

// Draws "(glyph) text" ending at right; returns the left edge
int drawHint(SDL_Surface *c, const Fonts &fonts, const char *glyph, const char *text, int right) {
    int w = 0;
    TTF_SizeUTF8(fonts.small, text, &w, NULL);
    int textX = right - w;
    drawText(c, fonts.small, text, TEXT, textX, FOOTER_Y + 22, LEFT);
    drawButtonGlyph(c, fonts.small, glyph, textX - 24, FOOTER_Y + 22 + TTF_FontHeight(fonts.small) / 2);
    return textX - 24 - 14 - 36;
}

void drawStatus(SDL_Surface *c, const Fonts &fonts, int battery) {
    int right = SCREEN_W - 60;
    if (battery >= 0) {
        // Battery outline with level, then the percentage to its left
        SDL_Rect body = {right - 40, 40, 36, 18};
        fillRoundRect(c, body, 3, mapRgb(c, TEXT));
        SDL_Rect inner = {body.x + 2, body.y + 2, body.w - 4, body.h - 4};
        SDL_FillRect(c, &inner, mapRgb(c, BG));
        SDL_Rect level = {inner.x + 1, inner.y + 1, (inner.w - 2) * battery / 100, inner.h - 2};
        SDL_FillRect(c, &level, mapRgb(c, battery <= 15 ? Rgb{230, 60, 60} : TEXT));
        SDL_Rect nub = {body.x + body.w, body.y + 5, 3, 8};
        SDL_FillRect(c, &nub, mapRgb(c, TEXT));
        right -= 52;
        char pct[16];
        snprintf(pct, sizeof(pct), "%d%%", battery);
        right -= drawText(c, fonts.small, pct, TEXT, right, 34, RIGHT) + 24;
    }
    // Console's local time (newlib's localtime() does not know its time zone)
    char clock[16];
    u64 now;
    TimeCalendarTime cal;
    TimeCalendarAdditionalInfo info;
    if (R_SUCCEEDED(timeGetCurrentTime(TimeType_UserSystemClock, &now)) &&
        R_SUCCEEDED(timeToCalendarTimeWithMyRule(now, &cal, &info))) {
        snprintf(clock, sizeof(clock), "%02d:%02d", cal.hour, cal.minute);
    } else {
        time_t t = time(NULL);
        strftime(clock, sizeof(clock), "%H:%M", localtime(&t));
    }
    drawText(c, fonts.medium, clock, TEXT, right, 30, RIGHT);
}

void drawFrame(SDL_Surface *c, const Fonts &fonts, const std::vector<PickerGame> &games,
               const std::vector<SDL_Surface *> &thumbs, int sel, int first,
               double t, int battery) {
    SDL_FillRect(c, NULL, mapRgb(c, BG));

    drawText(c, fonts.medium, "mkxp-z", TEXT, 60, 30, LEFT);
    drawStatus(c, fonts, battery);

    for (int i = first; i < (int)games.size(); ++i) {
        int x = ROW_X + (i - first) * (TILE + TILE_GAP);
        if (x >= SCREEN_W)
            break;
        if (i == sel) {
            // Pulsing cursor with a thin gap, like the home menu
            Rgb a = lerp(ACCENT, ACCENT_HI, 0.5 + 0.5 * sin(t * 4.0));
            fillRoundRect(c, {x - 8, TILE_Y - 8, TILE + 16, TILE + 16}, TILE_RADIUS + 6, mapRgb(c, a));
            fillRoundRect(c, {x - 3, TILE_Y - 3, TILE + 6, TILE + 6}, TILE_RADIUS + 2, mapRgb(c, BG));
            std::string label = fitText(fonts.title, games[i].name, SCREEN_W - x - 60);
            drawText(c, fonts.title, label, ACCENT, x, TILE_Y - 64, LEFT);
        }
        SDL_Rect r = {x, TILE_Y, TILE, TILE};
        if (thumbs[i])
            SDL_BlitSurface(thumbs[i], NULL, c, &r);
        else
            fillRoundRect(c, r, TILE_RADIUS, mapRgb(c, TILE_BG));
    }

    SDL_Rect line = {30, FOOTER_Y, SCREEN_W - 60, 1};
    SDL_FillRect(c, &line, mapRgb(c, LINE));
    char count[32];
    snprintf(count, sizeof(count), "%d / %d", sel + 1, (int)games.size());
    drawText(c, fonts.small, count, TEXT_DIM, 60, FOOTER_Y + 22, LEFT);
    int right = drawHint(c, fonts, "B", "Exit to hbmenu", SCREEN_W - 60);
    drawHint(c, fonts, "A", "Start", right);
}

void present(Framebuffer &fb, SDL_Surface *c) {
    u32 stride;
    u8 *dst = (u8 *)framebufferBegin(&fb, &stride);
    for (int y = 0; y < SCREEN_H; ++y)
        memcpy(dst + y * stride, (u8 *)c->pixels + y * c->pitch, SCREEN_W * 4);
    framebufferEnd(&fb);
}

TTF_Font *openSharedFont(const PlFontData &font, int size) {
    return TTF_OpenFontRW(SDL_RWFromConstMem(font.address, font.size), 1, size);
}

} // namespace

PickerResult pickerUiRun(const std::vector<PickerGame> &games, int &sel) {
    // The console's own font, so it looks like the system UI
    if (R_FAILED(plInitialize(PlServiceType_User)))
        return PICKER_UNAVAILABLE;
    PlFontData font;
    Fonts fonts;
    SDL_Surface *canvas = NULL;
    bool ttf = false;
    PickerResult result = PICKER_UNAVAILABLE;

    if (R_SUCCEEDED(plGetSharedFontByType(&font, PlSharedFontType_Standard)) &&
        TTF_Init() == 0) {
        ttf = true;
        fonts.small = openSharedFont(font, 22);
        fonts.medium = openSharedFont(font, 28);
        fonts.title = openSharedFont(font, 34);
        fonts.initials = openSharedFont(font, 96);
        canvas = SDL_CreateRGBSurfaceWithFormat(0, SCREEN_W, SCREEN_H, 32, SDL_PIXELFORMAT_RGBA32);
    }

    Framebuffer fb;
    if (fonts.small && fonts.medium && fonts.title && fonts.initials && canvas &&
        R_SUCCEEDED(framebufferCreate(&fb, nwindowGetDefault(), SCREEN_W, SCREEN_H,
                                      PIXEL_FORMAT_RGBA_8888, 2))) {
        framebufferMakeLinear(&fb);
        int battery = -1;
        bool psm = R_SUCCEEDED(psmInitialize());

        // Thumbnails can take a moment to decode
        SDL_FillRect(canvas, NULL, mapRgb(canvas, BG));
        drawText(canvas, fonts.medium, "Loading games...", TEXT_DIM, SCREEN_W / 2, SCREEN_H / 2 - 20, CENTER);
        present(fb, canvas);
        std::vector<SDL_Surface *> thumbs;
        for (const PickerGame &g : games)
            thumbs.push_back(makeThumb(g, fonts));

        PadState pad;
        padInitializeDefault(&pad);
        int first = std::max(0, sel - VISIBLE_TILES + 1);
        u64 heldSince = 0, lastRepeat = 0;
        result = PICKER_QUIT;

        while (appletMainLoop()) {
            padUpdate(&pad);
            u64 down = padGetButtonsDown(&pad);
            u64 held = padGetButtons(&pad);
            u64 now = armTicksToNs(armGetSystemTick());

            if (down & (HidNpadButton_Plus | HidNpadButton_B))
                break; // back to hbmenu
            if (down & HidNpadButton_A) {
                result = PICKER_PICKED;
                break;
            }

            // Left/right, repeating while held
            int step = 0;
            u64 dirs = HidNpadButton_AnyLeft | HidNpadButton_AnyRight;
            if (down & dirs) {
                heldSince = lastRepeat = now;
                step = (down & HidNpadButton_AnyLeft) ? -1 : 1;
            } else if ((held & dirs) && now - heldSince > 400000000ULL &&
                       now - lastRepeat > 110000000ULL) {
                lastRepeat = now;
                step = (held & HidNpadButton_AnyLeft) ? -1 : 1;
            }
            if (step)
                sel = std::max(0, std::min((int)games.size() - 1, sel + step));
            if (sel < first)
                first = sel;
            else if (sel >= first + VISIBLE_TILES)
                first = sel - VISIBLE_TILES + 1;

            u32 pct;
            if (psm && R_SUCCEEDED(psmGetBatteryChargePercentage(&pct)))
                battery = (int)pct;

            drawFrame(canvas, fonts, games, thumbs, sel, first, now / 1e9, battery);
            present(fb, canvas); // waits for a free buffer (vsync)
        }

        for (SDL_Surface *s : thumbs)
            SDL_FreeSurface(s);
        if (psm)
            psmExit();
        framebufferClose(&fb);
    }

    if (canvas)
        SDL_FreeSurface(canvas);
    for (TTF_Font *f : {fonts.small, fonts.medium, fonts.title, fonts.initials})
        if (f)
            TTF_CloseFont(f);
    if (ttf)
        TTF_Quit();
    plExit();
    return result;
}

#endif // __SWITCH__
