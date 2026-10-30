/*
** main.cpp
**
** This file is part of mkxp.
**
** Copyright (C) 2013 - 2021 Amaryllis Kulla <ancurio@mapleshrine.eu>
**
** mkxp is free software: you can redistribute it and/or modify
** it under the terms of the GNU General Public License as published by
** the Free Software Foundation, either version 2 of the License, or
** (at your option) any later version.
**
** mkxp is distributed in the hope that it will be useful,
** but WITHOUT ANY WARRANTY; without even the implied warranty of
** MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
** GNU General Public License for more details.
**
** You should have received a copy of the GNU General Public License
** along with mkxp.  If not, see <http://www.gnu.org/licenses/>.
*/

#ifndef MKXPZ_BUILD_XCODE
#include "icon.png.xxd"
#include "switch-trace.h"
// SWITCH_OPENAL_PATCH
#endif

#ifdef __SWITCH__
#include <AL/alc.h>
#else
#include <alc.h>
#endif
// SWITCH_OPENAL_PATCH

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_sound.h>
#include <SDL_ttf.h>

#include <assert.h>
#include <string.h>
#include <string>
#include <unistd.h>
#include <regex>

#include "binding.h"
#include "sharedstate.h"
#include "eventthread.h"
#include "util/debugwriter.h"
#include "util/exception.h"
#include "display/gl/gl-debug.h"
#include "display/gl/gl-fun.h"

#include "filesystem/filesystem.h"

#include "system/system.h"

#if defined(__WIN32__)
#include "resource.h"
#include <Winsock2.h>
#include "util/win-consoleutils.h"

// Try to work around buggy GL drivers that tend to be in Optimus laptops
// by forcing MKXP to use the dedicated card instead of the integrated one
#include <windows.h>
extern "C" {
__declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
__declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;
}
#endif

#ifdef MKXPZ_STEAM
#include "steamshim_child.h"
#endif

#ifdef MKXPZ_BUILD_XCODE
#include <Availability.h>
#include "TouchBar.h"
#if !defined(__MAC_10_15) || __MAC_OS_X_VERSION_MAX_ALLOWED < __MAC_10_15
#define MKXPZ_INIT_GL_LATER
#endif
#endif

#ifndef MKXPZ_INIT_GL_LATER
#define GLINIT_SHOWERROR(s) showInitError(s)
#else
#define GLINIT_SHOWERROR(s) rgssThreadError(threadData, s)
#endif

static void rgssThreadError(RGSSThreadData *rtData, const std::string &msg);
static void showInitError(const std::string &msg);

static inline const char *glGetStringInt(GLenum name) {
  return (const char *)gl.GetString(name);
}

static void printGLInfo() {
#ifdef __SWITCH__
    const char* renderer_c = (const char*)gl.GetString(GL_RENDERER);
    const char* version_c  = (const char*)gl.GetString(GL_VERSION);
    const char* vendor_c   = (const char*)gl.GetString(GL_VENDOR);

    Debug() << "Backend      : GLES";
    Debug() << "GL Vendor    : " << (vendor_c ? vendor_c : "Unknown");
    Debug() << "GL Renderer  : " << (renderer_c ? renderer_c : "Unknown");
    Debug() << "GL Version   : " << (version_c ? version_c : "Unknown");

    // Skip GLSL version / regex parsing for now
#else
    const std::string renderer(glGetStringInt(GL_RENDERER));
    const std::string version(glGetStringInt(GL_VERSION));
    std::regex rgx("ANGLE \\((.+), ANGLE Metal Renderer: (.+), Version (.+)\\)");
    std::smatch matches;
    if (std::regex_search(renderer, matches, rgx)) {
        Debug() << "Backend           :" << "Metal";
        Debug() << "Metal Device      :" << matches[2] << "(" + matches[1].str() + ")";
        Debug() << "Renderer Version  :" << matches[3].str();
        std::smatch vmatches;
        if (std::regex_search(version, vmatches, std::regex("\\(ANGLE (.+) git hash: .+\\)"))) {
            Debug() << "ANGLE Version     :" << vmatches[1].str();
        }
        return;
    }

    Debug() << "Backend      :" << "OpenGL";
    Debug() << "GL Vendor    :" << glGetStringInt(GL_VENDOR);
    Debug() << "GL Renderer  :" << renderer;
    Debug() << "GL Version   :" << version;
    Debug() << "GLSL Version :" << glGetStringInt(GL_SHADING_LANGUAGE_VERSION);
#endif
}


static SDL_GLContext initGL(SDL_Window *win, Config &conf,
                            RGSSThreadData *threadData);

#ifdef __SWITCH__
extern "C" void switch_enable_logging();
extern "C" void switch_boot_mark(const char *msg);
extern "C" bool switch_pick_game(char *out, size_t outSize);
extern "C" void switch_return_to_picker(const char *argv0);
#define BOOT_MARK(msg) switch_boot_mark(msg)
#else
#define BOOT_MARK(msg) do {} while (0)
#endif

int rgssThreadFun(void *userdata) {
  RGSSThreadData *threadData = static_cast<RGSSThreadData *>(userdata);

#ifdef MKXPZ_INIT_GL_LATER
  threadData->glContext =
      initGL(threadData->window, threadData->config, threadData);
  if (!threadData->glContext)
    return 0;
#else
  SDL_GL_MakeCurrent(threadData->window, threadData->glContext);
#endif

  SWITCH_TRACE("RGSS thread: GL init done\n");

  /* Setup AL context */
  ALCcontext *alcCtx = alcCreateContext(threadData->alcDev, 0);

  if (!alcCtx) {
    printf("RGSS thread: OpenAL context creation FAILED\n");
    fflush(stdout);
    rgssThreadError(threadData, "Error creating OpenAL context");
    return 0;
  }

  alcMakeContextCurrent(alcCtx);
  SWITCH_TRACE("RGSS thread: OpenAL context created\n");

  try {
    SWITCH_TRACE("RGSS thread: before SharedState::initInstance\n");
    SharedState::initInstance(threadData);
    SWITCH_TRACE("RGSS thread: after SharedState::initInstance\n");
  } catch (const Exception &exc) {
    printf("RGSS thread: EXCEPTION in SharedState::initInstance: %s\n", exc.msg.c_str());
    fflush(stdout);
    rgssThreadError(threadData, exc.msg);
    alcDestroyContext(alcCtx);

    return 0;
  }

  SWITCH_TRACE("RGSS thread: before scriptBinding->execute()\n");

  /* Start script execution */
  scriptBinding->execute();

  SWITCH_TRACE("RGSS thread: after scriptBinding->execute()\n");
  BOOT_MARK("rgss: scriptBinding->execute returned\n");

  threadData->rqTermAck.set();
  threadData->ethread->requestTerminate();

  BOOT_MARK("rgss: before SharedState::finiInstance\n");
  SharedState::finiInstance();
  BOOT_MARK("rgss: after SharedState::finiInstance\n");

  BOOT_MARK("rgss: before alcDestroyContext\n");
  alcDestroyContext(alcCtx);
  BOOT_MARK("rgss: after alcDestroyContext\n");

  BOOT_MARK("rgss: thread returning\n");
  return 0;
}

static void printRgssVersion(int ver) {
  const char *const makers[] = {"", "XP", "VX", "VX Ace"};

  char buf[128];
  snprintf(buf, sizeof(buf), "RGSS version %d (RPG Maker %s)", ver,
           makers[ver]);

  Debug() << buf;
}

static void rgssThreadError(RGSSThreadData *rtData, const std::string &msg) {
  rtData->rgssErrorMsg = msg;
  rtData->ethread->requestTerminate();
  rtData->rqTermAck.set();
}

static void showInitError(const std::string &msg) {
  Debug() << msg;
  SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, "mkxp-z", msg.c_str(), 0);
}

static void setupWindowIcon(const Config &conf, SDL_Window *win) {
  SDL_RWops *iconSrc;

  if (conf.iconPath.empty())
#ifndef MKXPZ_BUILD_XCODE
    iconSrc = SDL_RWFromConstMem(___assets_icon_png, ___assets_icon_png_len);
#else
    iconSrc = SDL_RWFromFile(mkxp_fs::getPathForAsset("icon", "png").c_str(), "rb");
#endif
  else
    iconSrc = SDL_RWFromFile(conf.iconPath.c_str(), "rb");

  SDL_Surface *iconImg = IMG_Load_RW(iconSrc, SDL_TRUE);

  if (iconImg) {
    SDL_SetWindowIcon(win, iconImg);
    SDL_FreeSurface(iconImg);
  }
}

int main(int argc, char *argv[]) {
#ifdef __SWITCH__
    // Pick the game before SDL takes over the display
    char switchGameDir[512]{};
    switch_boot_mark("main: before switch_pick_game\n");
    if (!switch_pick_game(switchGameDir, sizeof(switchGameDir))) {
        switch_boot_mark("main: picker returned false\n");
        return 0;
    }
    switch_boot_mark("main: after switch_pick_game\n");
    switch_enable_logging();
    switch_boot_mark("main: logging enabled\n");
    printf("mkxp-z: game folder '%s'\n", switchGameDir);
#endif
    SWITCH_TRACE("mkxp-z: entering main()\n");

    // Print arguments for debugging
    for(int i = 0; i < argc; i++) {
        SWITCH_TRACE("Arg %d: %s\n", i, argv[i]);
    }

    SDL_SetHint(SDL_HINT_VIDEO_MINIMIZE_ON_FOCUS_LOSS, "0");
    SDL_SetHint(SDL_HINT_ACCELEROMETER_AS_JOYSTICK, "0");

#ifdef GLES2_HEADER
    SDL_SetHint(SDL_HINT_OPENGL_ES_DRIVER, "1");
#endif

    BOOT_MARK("main: before SDL_Init\n");
    SWITCH_TRACE("mkxp-z: before SDL_Init\n");

    /* initialize SDL first */
    if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_GAMECONTROLLER | SDL_INIT_TIMER) < 0) {
      printf("mkxp-z: SDL_Init failed: %s\n", SDL_GetError());
      fflush(stdout);
      showInitError(std::string("Error initializing SDL: ") + SDL_GetError());
      return 0;
    }

    BOOT_MARK("main: after SDL_Init\n");
    SWITCH_TRACE("mkxp-z: after SDL_Init\n");

    if (!EventThread::allocUserEvents()) {
      printf("mkxp-z: EventThread::allocUserEvents failed\n");
      fflush(stdout);
      showInitError("Error allocating SDL user events");
      return 0;
    }

    BOOT_MARK("main: after allocUserEvents\n");
    SWITCH_TRACE("mkxp-z: after EventThread::allocUserEvents\n");

#ifndef WORKDIR_CURRENT
    char dataDir[512]{};
#if defined(__linux__)
    char *tmp{};
    tmp = getenv("SRCDIR");
    if (tmp) {
      strncpy(dataDir, tmp, sizeof(dataDir));
    }
#endif
    if (!dataDir[0]) {

#ifdef __SWITCH__
    strncpy(dataDir, switchGameDir, sizeof(dataDir));
    dataDir[sizeof(dataDir) - 1] = '\0';

#else
        strncpy(dataDir, mkxp_fs::getDefaultGameRoot().c_str(), sizeof(dataDir));
        dataDir[sizeof(dataDir) - 1] = '\0';
#endif
    }
    mkxp_fs::setCurrentDirectory(dataDir);
#endif
    
    BOOT_MARK("main: before Config read\n");

    /* now we load the config */
    Config conf;

    try {
        conf.read(argc, argv);
    } catch (const std::exception &e) {
        printf("CRASH in Config::read: %s\n", e.what());
        fflush(stdout);
        showInitError(std::string("Config load failed: ") + e.what());
        return 0;
    } catch (...) {
        printf("CRASH in Config::read: Unknown exception\n");
        fflush(stdout);
        showInitError("Config load failed: Unknown exception");
        return 0;
    }

    BOOT_MARK("main: after Config read\n");

#ifdef __SWITCH__
    // No MiniFFI on Switch: Ruby stand-ins from RomFS (switch/romfs-root/
    // preload) run before the game's own preload scripts.
    conf.preloadScripts.insert(conf.preloadScripts.begin(), {
        "romfs:/preload/win32api_stub.rb",
        "romfs:/preload/win32_wrap.rb",
        // Shows "Loading <title>..." while the game's scripts load
        "romfs:/preload/loading_screen.rb",
    });
#endif

#if defined(__WIN32__)
    // Create a debug console in debug mode
    if (conf.winConsole) {
      if (setupWindowsConsole()) {
        reopenWindowsStreams();
      } else {
        char buf[200];
        snprintf(buf, sizeof(buf), "Error allocating console: %lu",
                GetLastError());
        showInitError(std::string(buf));
      }
    }
#endif

#ifdef MKXPZ_STEAM
    if (!STEAMSHIM_init()) {
      showInitError("Failed to initialize Steamworks. The application cannot "
                    "continue launching.");
      SDL_Quit();
      return 0;
    }
#endif

    if (conf.windowTitle.empty())
      conf.windowTitle = conf.game.title;

    assert(conf.rgssVersion >= 1 && conf.rgssVersion <= 3);
    printRgssVersion(conf.rgssVersion);
    BOOT_MARK("main: after rgss version\n");

    SWITCH_TRACE("mkxp-z: before IMG_Init\n");

    int imgFlags = IMG_INIT_PNG | IMG_INIT_JPG;
    if (IMG_Init(imgFlags) != imgFlags) {
      showInitError(std::string("Error initializing SDL_image: ") +
                    SDL_GetError());
      SDL_Quit();

#ifdef MKXPZ_STEAM
      STEAMSHIM_deinit();
#endif

      return 0;
    }

    BOOT_MARK("main: after IMG_Init\n");
    SWITCH_TRACE("mkxp-z: after IMG_Init\n");

    if (TTF_Init() < 0) {
      showInitError(std::string("Error initializing SDL_ttf: ") +
                    SDL_GetError());
      IMG_Quit();
      SDL_Quit();

#ifdef MKXPZ_STEAM
      STEAMSHIM_deinit();
#endif

      return 0;
    }

    BOOT_MARK("main: after TTF_Init\n");
    SWITCH_TRACE("mkxp-z: after TTF_Init\n");

#ifdef __SWITCH__
// TODO grant: SDL_sound doesn't work on switch QUICK TEST DISABLING SOUND
    if (Sound_Init() == 0) {
        printf("Warning: SDL_sound failed to init, continuing anyway\n");
    }
#else
    if (Sound_Init() == 0) {
        showInitError(std::string("Error initializing SDL_sound: ") +
                      Sound_GetError());
        TTF_Quit();
        IMG_Quit();
        SDL_Quit();

#ifdef MKXPZ_STEAM
        STEAMSHIM_deinit();
#endif

        return 0;
    }
#endif

    BOOT_MARK("main: after Sound_Init\n");

#if defined(__WIN32__)
    WSAData wsadata = {0};
    if (WSAStartup(0x101, &wsadata) || wsadata.wVersion != 0x101) {
      char buf[200];
      snprintf(buf, sizeof(buf), "Error initializing winsock: %08X",
               WSAGetLastError());
      showInitError(
          std::string(buf)); // Not an error worth ending the program over
    }
#endif

    SDL_Window *win;
    Uint32 winFlags = SDL_WINDOW_OPENGL | SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_ALLOW_HIGHDPI;

    if (conf.winResizable)
      winFlags |= SDL_WINDOW_RESIZABLE;
    if (conf.fullscreen)
      winFlags |= SDL_WINDOW_FULLSCREEN_DESKTOP;
    
#ifdef GLES2_HEADER
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 2);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);

    // LoadLibrary properly initializes EGL, it won't work otherwise.
    // Doesn't completely do it though, needs a small patch to SDL
#ifdef MKXPZ_BUILD_XCODE
    SDL_setenv("ANGLE_DEFAULT_PLATFORM", (conf.preferMetalRenderer) ? "metal" : "opengl", true);
    SDL_GL_LoadLibrary("@rpath/libEGL.dylib");
#endif
#endif

    BOOT_MARK("main: before CreateWindow\n");
    SWITCH_TRACE("mkxp-z: before SDL_CreateWindow\n");
    
    int createW = conf.defScreenW, createH = conf.defScreenH;
#ifdef __SWITCH__
    // The window is always the whole screen on Switch. Created at the game's
    // resolution, the display would stretch it to fill the screen; created at
    // the display's size, mkxp-z scales the game itself and keeps its aspect
    // ratio (fixedAspectRatio).
    SDL_DisplayMode desktop;
    if (SDL_GetDesktopDisplayMode(0, &desktop) == 0) {
        createW = desktop.w;
        createH = desktop.h;
    }
#endif
    win = SDL_CreateWindow(conf.windowTitle.c_str(), SDL_WINDOWPOS_UNDEFINED,
                           SDL_WINDOWPOS_UNDEFINED, createW, createH, winFlags);

    if (!win) {
      showInitError(std::string("Error creating window: ") + SDL_GetError());

#ifdef MKXPZ_STEAM
      STEAMSHIM_deinit();
#endif
      return 0;
    }
    
    BOOT_MARK("main: after CreateWindow\n");
    SWITCH_TRACE("mkxp-z: after SDL_CreateWindow\n");

#ifdef MKXPZ_BUILD_XCODE
    {
        std::string downloadsPath = "/Users/" + mkxp_sys::getUserName() + "/Downloads";
        
        if (mkxp_fs::getCurrentDirectory().find(downloadsPath) == 0) {
            showInitError(conf.game.title +
                          " cannot run from the Downloads directory.\n\n" +
                          "Please move the application to the Applications folder (or anywhere else) " +
                          "and try again.");
#ifdef MKXPZ_STEAM
            STEAMSHIM_deinit();
#endif
            return 0;
        }
    }
#endif
    
#if defined(MKXPZ_BUILD_XCODE)
#define DEBUG_FSELECT_MSG "Select the folder from which to load game files. This is the folder containing the game's INI."
#define DEBUG_FSELECT_PROMPT "Load Game"
    if (conf.manualFolderSelect) {
        std::string dataDirStr = mkxp_fs::selectPath(win, DEBUG_FSELECT_MSG, DEBUG_FSELECT_PROMPT);
        if (!dataDirStr.empty()) {
            conf.gameFolder = dataDirStr;
            mkxp_fs::setCurrentDirectory(dataDirStr.c_str());
            Debug() << "Current directory set to" << dataDirStr;
            conf.read(argc, argv);
            conf.readGameINI();
        }
    }
#endif

    /* OSX and Windows have their own native ways of
     * dealing with icons; don't interfere with them */
#ifdef __LINUX__
    setupWindowIcon(conf, win);
#else
    (void)setupWindowIcon;
#endif

    ALCdevice *alcDev = alcOpenDevice(0);

    if (!alcDev) {
      showInitError("Could not detect an available audio device.");
      SDL_DestroyWindow(win);
      TTF_Quit();
      IMG_Quit();
      SDL_Quit();

#ifdef MKXPZ_STEAM
      STEAMSHIM_deinit();
#endif
      return 0;
    }

    BOOT_MARK("main: after alcOpenDevice\n");
    SWITCH_TRACE("mkxp-z: after alcOpenDevice\n");
    SDL_DisplayMode mode;
    SDL_GetDisplayMode(0, 0, &mode);

    /* Can't sync to display refresh rate if its value is unknown */
    if (!mode.refresh_rate)
      conf.syncToRefreshrate = false;

    EventThread eventThread;

    BOOT_MARK("main: before initGL\n");
#ifndef MKXPZ_INIT_GL_LATER
    SDL_GLContext glCtx = initGL(win, conf, 0);
#else
    SDL_GLContext glCtx = NULL;
#endif
    BOOT_MARK("main: after initGL\n");

    RGSSThreadData rtData(&eventThread, argv[0], win, alcDev, mode.refresh_rate,
                          mkxp_sys::getScalingFactor(), conf, glCtx);

    int winW, winH, drwW, drwH;
    SDL_GetWindowSize(win, &winW, &winH);
    rtData.windowSizeMsg.post(Vec2i(winW, winH));
    
    SDL_GL_GetDrawableSize(win, &drwW, &drwH);
    rtData.drawableSizeMsg.post(Vec2i(drwW, drwH));

    /* Load and post key bindings */
    rtData.bindingUpdateMsg.post(loadBindings(conf));
    
#ifdef MKXPZ_BUILD_XCODE
    // Create Touch Bar
    initTouchBar(win, conf);
#endif

    /* Start RGSS thread */
    BOOT_MARK("main: before RGSS thread\n");
    SWITCH_TRACE("mkxp-z: before SDL_CreateThread (RGSS)\n");
    SDL_Thread *rgssThread = SDL_CreateThread(rgssThreadFun, "rgss", &rtData);
    BOOT_MARK("main: RGSS thread started\n");

    SWITCH_TRACE("mkxp-z: after SDL_CreateThread, before eventThread.process\n");

    /* Start event processing */
    eventThread.process(rtData);

    BOOT_MARK("main: eventThread.process returned\n");
    SWITCH_TRACE("mkxp-z: after eventThread.process, before rqTerm.set\n");

    /* Request RGSS thread to stop */
    BOOT_MARK("main: before rqTerm.set\n");
    rtData.rqTerm.set();

    /* Wait for RGSS thread response */
    for (int i = 0; i < 1000; ++i) {
      /* We can stop waiting when the request was ack'd */
      if (rtData.rqTermAck) {
        Debug() << "RGSS thread ack'd request after" << i * 10 << "ms";
        break;
      }

      /* Give RGSS thread some time to respond */
      SDL_Delay(10);
    }
    BOOT_MARK(rtData.rqTermAck ? "main: rqTermAck set, before SDL_WaitThread\n"
                               : "main: rqTermAck NOT set, skipping SDL_WaitThread\n");

    /* If RGSS thread ack'd request, wait for it to shutdown,
     * otherwise abandon hope and just end the process as is. */
    if (rtData.rqTermAck) {
      SDL_WaitThread(rgssThread, 0);
      BOOT_MARK("main: after SDL_WaitThread\n");
    } else {
      SDL_ShowSimpleMessageBox(
          SDL_MESSAGEBOX_ERROR, conf.game.title.c_str(),
          std::string("The RGSS script seems to be stuck. "+conf.game.title+" will now force quit.").c_str(),
          win);
      BOOT_MARK("main: after stuck-script message box\n");
    }

    if (!rtData.rgssErrorMsg.empty()) {
      Debug() << rtData.rgssErrorMsg;
      SDL_ShowSimpleMessageBox(SDL_MESSAGEBOX_ERROR, conf.game.title.c_str(),
                               rtData.rgssErrorMsg.c_str(), win);
      BOOT_MARK("main: after rgssErrorMsg box\n");
    }

    if (rtData.glContext) {
      BOOT_MARK("main: before SDL_GL_DeleteContext\n");
      SDL_GL_DeleteContext(rtData.glContext);
      BOOT_MARK("main: after SDL_GL_DeleteContext\n");
    }

    SWITCH_TRACE("mkxp-z: main() reaching shutdown path\n");

    /* Clean up any remainin events */
    BOOT_MARK("main: before eventThread.cleanup\n");
    eventThread.cleanup();
    BOOT_MARK("main: after eventThread.cleanup\n");

    Debug() << "Shutting down.";
    BOOT_MARK("main: after 'Shutting down' debug line\n");

    BOOT_MARK("main: before alcCloseDevice\n");
    alcCloseDevice(alcDev);
    BOOT_MARK("main: after alcCloseDevice\n");

    SDL_DestroyWindow(win);
    BOOT_MARK("main: after SDL_DestroyWindow\n");

#if defined(__WIN32__)
    if (wsadata.wVersion)
      WSACleanup();
#endif

#ifdef MKXPZ_STEAM
    STEAMSHIM_deinit();
#endif
    Sound_Quit();
    BOOT_MARK("main: after Sound_Quit\n");
    TTF_Quit();
    BOOT_MARK("main: after TTF_Quit\n");
    IMG_Quit();
    BOOT_MARK("main: after IMG_Quit\n");
    SDL_Quit();
    BOOT_MARK("main: after SDL_Quit\n");
#ifdef __SWITCH__
    switch_return_to_picker(argc > 0 ? argv[0] : NULL);
    BOOT_MARK("main: after switch_return_to_picker\n");
#endif

    SWITCH_TRACE("mkxp-z: leaving main()\n");
    return 0;
}

static SDL_GLContext initGL(SDL_Window *win, Config &conf,
                            RGSSThreadData *threadData) {
  SDL_GLContext glCtx{};

  /* Setup GL context. Must be done in main thread since macOS 10.15 */
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);
    
  if (conf.debugMode)
    SDL_GL_SetAttribute(SDL_GL_CONTEXT_FLAGS, SDL_GL_CONTEXT_DEBUG_FLAG);

  glCtx = SDL_GL_CreateContext(win);

  if (!glCtx) {
    GLINIT_SHOWERROR(std::string("Could not create OpenGL context: ") + SDL_GetError());
    return 0;
  }

  try {
    initGLFunctions();
  } catch (const Exception &exc) {
    GLINIT_SHOWERROR(exc.msg);
    SDL_GL_DeleteContext(glCtx);

    return 0;
  }

  if (!conf.enableBlitting)
    gl.BlitFramebuffer = 0;

  gl.ClearColor(0, 0, 0, 1);
  gl.Clear(GL_COLOR_BUFFER_BIT);
  SDL_GL_SwapWindow(win);

  printGLInfo();

  bool vsync = conf.vsync || conf.syncToRefreshrate;
  SDL_GL_SetSwapInterval(vsync ? 1 : 0);

  // GLDebugLogger dLogger;
  return glCtx;
}
