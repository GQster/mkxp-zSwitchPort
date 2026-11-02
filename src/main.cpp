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

#ifndef VK_NO_PROTOTYPES
#  define VK_NO_PROTOTYPES
#endif

#include "icon.png.xxd"
#include "switch-trace.h"

#include <alc.h>
#include <alext.h>

#include <SDL.h>
#include <SDL_image.h>
#include <SDL_sound.h>
#include <SDL_ttf.h>

#include <cassert>
#include <cstring>
#include <string>
#include <unistd.h>

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
#include <processenv.h>
#include <winsock2.h>
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

#ifdef __APPLE__
#include <Availability.h>
#include "TouchBar.h"
#endif

#if !defined(__ANDROID__) && !defined(__APPLE__) && !defined(_WIN32) && !defined(__SWITCH__)
#  define MKXPZ_CHECK_FOR_WAYLAND_SUPPORT
#endif

#if defined(MKXPZ_HAVE_ANGLE) && defined(MKXPZ_HAVE_ANGLE_VULKAN)
#  define MKXPZ_CHECK_FOR_LAVAPIPE
#  include <volk.h>
#endif

#ifndef MKXPZ_INIT_GL_LATER
#define GLINIT_SHOWERROR(s) showInitError(s)
#else
#define GLINIT_SHOWERROR(s) rgssThreadError(threadData, s)
#endif

#ifdef MKXPZ_HAVE_ANGLE
bool mkxp_use_angle = true;
#endif // MKXPZ_HAVE_ANGLE

static void rgssThreadError(RGSSThreadData *rtData, const std::string &msg);
static void showInitError(const std::string &msg);

static void mkxp_setenv(const char *key, const char *value) {
#ifdef _WIN32
  SetEnvironmentVariableA(key, value);
#else
  if (value != nullptr) {
    setenv(key, value, true);
  } else {
    unsetenv(key);
  }
#endif
}

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
extern "C" void switch_setup_openal_debug();
extern "C" bool switch_pick_game(char *out, size_t outSize);
extern "C" void switch_controls_load_active();
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
  static const ALCint attrs[] = {
    /* HRTF is explicitly disabled here because it results in poor-quality audio
     * when enabled (see https://github.com/mkxp-z/mkxp-z/issues/341). By
     * default, it's enabled when OpenAL Soft detects that the user is using
     * headphones for audio drivers that support detecting if the user is using
     * headphones, and disabled regardless of whether or not the user is using
     * headphones if the audio driver does not support this detection. The HRTF
     * is required for positional audio support, so we'll need to find a way
     * around the audio quality issues and inconsistent detection of whether or
     * not the user is using headphones once we have positional audio support. */
    ALC_HRTF_SOFT, ALC_FALSE,
    0
  };
  ALCcontext *alcCtx = alcCreateContext(threadData->alcDev, attrs);

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
    iconSrc = SDL_RWFromConstMem(mkxp_assets_icon_png, mkxp_assets_icon_png_len);
  else
    iconSrc = SDL_RWFromFile(conf.iconPath.c_str(), "rb");

  SDL_Surface *iconImg = IMG_Load_RW(iconSrc, SDL_TRUE);

  if (iconImg) {
    SDL_SetWindowIcon(win, iconImg);
    SDL_FreeSurface(iconImg);
  }
}

static SDL_Window *initVideo(const Config &conf) {
  Uint32 winFlags = SDL_WINDOW_OPENGL | SDL_WINDOW_INPUT_FOCUS | SDL_WINDOW_ALLOW_HIGHDPI;

  if (conf.winResizable)
    winFlags |= SDL_WINDOW_RESIZABLE;
  if (conf.fullscreen)
    winFlags |= SDL_WINDOW_FULLSCREEN_DESKTOP;

  if (SDL_Init(SDL_INIT_VIDEO) < 0) {
    return nullptr;
  }

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GetHintBoolean(SDL_HINT_OPENGL_ES_DRIVER, SDL_FALSE) ? SDL_GL_CONTEXT_PROFILE_ES : SDL_GL_CONTEXT_PROFILE_CORE | SDL_GL_CONTEXT_PROFILE_COMPATIBILITY);

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

  SDL_Window *window = SDL_CreateWindow(conf.windowTitle.c_str(), SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED, createW, createH, winFlags);
  if (window == nullptr) {
    SDL_QuitSubSystem(SDL_INIT_VIDEO);
  }
  return window;
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
    // Before the bindings are generated: a custom profile replaces the
    // controller bindings
    switch_controls_load_active();
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

    SDL_SetHint(SDL_HINT_IME_SHOW_UI, "1");

    SDL_SetHint(
      SDL_HINT_OPENGL_ES_DRIVER,
      SDL_GetHintBoolean(
        SDL_HINT_OPENGL_ES_DRIVER,
#ifdef MKXPZ_USE_GLES_BY_DEFAULT
        SDL_TRUE
#else
        SDL_FALSE
#endif // MKXPZ_USE_GLES_BY_DEFAULT
      ) != SDL_FALSE ? "1" : "0"
    );

#ifndef WORKDIR_CURRENT
    char dataDir[512]{};
#if defined(__linux__)
    char *tmp{};
    tmp = getenv("SRCDIR");
    if (tmp) {
      std::strncpy(dataDir, tmp, sizeof(dataDir));
    }
#endif
    if (!dataDir[0]) {
#ifdef __SWITCH__
      std::strncpy(dataDir, switchGameDir, sizeof(dataDir));
#else
      std::strncpy(dataDir, mkxp_fs::getDefaultGameRoot().c_str(), sizeof(dataDir));
#endif
      dataDir[sizeof(dataDir) - 1] = '\0';
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
    if (conf.windowTitle.empty())
      conf.windowTitle = conf.game.title;

    BOOT_MARK("main: after Config read\n");

#ifdef __SWITCH__
    // No MiniFFI on Switch: Ruby stand-ins from RomFS (switch/romfs-root/
    // preload) run before the game's own preload scripts.
    conf.preloadScripts.insert(conf.preloadScripts.begin(), {
        "romfs:/preload/log_sync.rb",
        "romfs:/preload/win32api_stub.rb",
        "romfs:/preload/win32_wrap.rb",
        // Shows "Loading <title>..." while the game's scripts load
        "romfs:/preload/loading_screen.rb",
        // Game Boy style Start/Select, B-to-run and ZL soft reset
        "romfs:/preload/switch_controls.rb",
        // Debug tracing only: logs what each slow frame spent its time on
        "romfs:/preload/perf_trace.rb",
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

    BOOT_MARK("main: before SDL_Init\n");
    SWITCH_TRACE("mkxp-z: before SDL_Init\n");

    /* initialize SDL first */
    if (SDL_Init(SDL_INIT_GAMECONTROLLER | SDL_INIT_TIMER) < 0) {
      printf("mkxp-z: SDL_Init failed: %s\n", SDL_GetError());
      fflush(stdout);
      showInitError(std::string("Error initializing SDL: ") + SDL_GetError());
      return 0;
    }

    BOOT_MARK("main: after SDL_Init\n");
    SWITCH_TRACE("mkxp-z: after SDL_Init\n");

    SDL_Window *win = nullptr;

#ifdef MKXPZ_CHECK_FOR_WAYLAND_SUPPORT
    {
      const char *sdl_videodriver = SDL_GetHint(SDL_HINT_VIDEODRIVER);
      if (sdl_videodriver == nullptr || sdl_videodriver[0] == 0) {
        /* Select SDL's Wayland video driver if SDL_VIDEODRIVER is unset and Wayland support is available on the user's machine */
        void *wayland_client = SDL_LoadObject(MKXPZ_WAYLAND_CLIENT_SONAME);
        void *wayland_cursor = SDL_LoadObject(MKXPZ_WAYLAND_CURSOR_SONAME);
        void *wayland_egl = SDL_LoadObject(MKXPZ_WAYLAND_EGL_SONAME);
        void *xkbcommon = SDL_LoadObject(MKXPZ_XKBCOMMON_SONAME);
        if (
          wayland_client != nullptr
            && wayland_cursor != nullptr
            && wayland_egl != nullptr
            && xkbcommon != nullptr
        ) {
          void *(*_wl_display_connect)(const char *name) = reinterpret_cast<void *(*)(const char *name)>(SDL_LoadFunction(wayland_client, "wl_display_connect"));
          void (*_wl_display_disconnect)(void *display) = reinterpret_cast<void (*)(void *display)>(SDL_LoadFunction(wayland_client, "wl_display_disconnect"));
          void *(*_wl_cursor_image_get_buffer)(void *image) = reinterpret_cast<void *(*)(void *image)>(SDL_LoadFunction(wayland_cursor, "wl_cursor_image_get_buffer"));
          void (*_wl_cursor_theme_destroy)(void *theme) = reinterpret_cast<void (*)(void *theme)>(SDL_LoadFunction(wayland_cursor, "wl_cursor_theme_destroy"));
          void *(*_wl_cursor_theme_get_cursor)(void *theme, const char *name) = reinterpret_cast<void *(*)(void *theme, const char *name)>(SDL_LoadFunction(wayland_cursor, "wl_cursor_theme_get_cursor"));
          void *(*_wl_cursor_theme_load)(const char *name, int size, void *shm) = reinterpret_cast<void *(*)(const char *name, int size, void *shm)>(SDL_LoadFunction(wayland_cursor, "wl_cursor_theme_load"));
          void *(*_wl_egl_window_create)(void *surface, int width, int height) = reinterpret_cast<void *(*)(void *surface, int width, int height)>(SDL_LoadFunction(wayland_egl, "wl_egl_window_create"));
          void (*_wl_egl_window_destroy)(void *egl_window) = reinterpret_cast<void (*)(void *egl_window)>(SDL_LoadFunction(wayland_egl, "wl_egl_window_destroy"));
          void (*_wl_egl_window_resize)(void *egl_window, int width, int height, int dx, int dy) = reinterpret_cast<void (*)(void *egl_window, int width, int height, int dx, int dy)>(SDL_LoadFunction(wayland_egl, "wl_egl_window_resize"));
          void *(*_xkb_context_new)(int flags) = reinterpret_cast<void *(*)(int flags)>(SDL_LoadFunction(xkbcommon, "xkb_context_new"));
          void (*_xkb_context_unref)(void *context) = reinterpret_cast<void (*)(void *context)>(SDL_LoadFunction(xkbcommon, "xkb_context_unref"));
          if (
            _wl_display_connect != nullptr
              && _wl_display_disconnect != nullptr
              && _wl_cursor_image_get_buffer != nullptr
              && _wl_cursor_theme_destroy != nullptr
              && _wl_cursor_theme_get_cursor != nullptr
              && _wl_cursor_theme_load != nullptr
              && _wl_egl_window_create != nullptr
              && _wl_egl_window_destroy != nullptr
              && _wl_egl_window_resize != nullptr
              && _xkb_context_new != nullptr
              && _xkb_context_unref != nullptr
          ) {
            void *display = _wl_display_connect(nullptr);
            if (display != nullptr) {
              _wl_display_disconnect(display);
              SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, "wayland", SDL_HINT_OVERRIDE);
            }
          }
        }
        if (xkbcommon != nullptr) {
          SDL_UnloadObject(xkbcommon);
        }
        if (wayland_cursor != nullptr) {
          SDL_UnloadObject(wayland_cursor);
        }
        if (wayland_client != nullptr) {
          SDL_UnloadObject(wayland_client);
        }
      }
      sdl_videodriver = SDL_GetHint(SDL_HINT_VIDEODRIVER);
      if (sdl_videodriver == nullptr || sdl_videodriver[0] == 0) {
        /* Select SDL's X11 video driver, with fallback to KMSDRM, if SDL_VIDEODRIVER is unset and X11 support is available on the user's machine */
        void *x11 = SDL_LoadObject(MKXPZ_X11_SONAME);
        void *xcursor = SDL_LoadObject(MKXPZ_XCURSOR_SONAME);
        void *xext = SDL_LoadObject(MKXPZ_XEXT_SONAME);
        void *xfixes = SDL_LoadObject(MKXPZ_XFIXES_SONAME);
        void *xi = SDL_LoadObject(MKXPZ_XI_SONAME);
        void *xrandr = SDL_LoadObject(MKXPZ_XRANDR_SONAME);
        if (
          x11 != nullptr
            && xcursor != nullptr
            && xext != nullptr
            && xfixes != nullptr
            && xi != nullptr
            && xrandr != nullptr
        ) {
          SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, "x11,kmsdrm", SDL_HINT_OVERRIDE);
        }
        if (x11 != nullptr) {
          SDL_UnloadObject(x11);
        }
        if (xcursor != nullptr) {
          SDL_UnloadObject(xcursor);
        }
        if (xext != nullptr) {
          SDL_UnloadObject(xext);
        }
        if (xfixes != nullptr) {
          SDL_UnloadObject(xfixes);
        }
        if (xi != nullptr) {
          SDL_UnloadObject(xi);
        }
        if (xrandr != nullptr) {
          SDL_UnloadObject(xrandr);
        }
      }
      sdl_videodriver = SDL_GetHint(SDL_HINT_VIDEODRIVER);
      if (sdl_videodriver == nullptr || sdl_videodriver[0] == 0) {
        /* Otherwise, use KMSDRM */
        SDL_SetHintWithPriority(SDL_HINT_VIDEODRIVER, "kmsdrm", SDL_HINT_OVERRIDE);
      }

      /* Prevent ANGLE from using Wayland if we haven't selected SDL's Wayland video driver */
      sdl_videodriver = SDL_GetHint(SDL_HINT_VIDEODRIVER);
      assert(sdl_videodriver != nullptr && sdl_videodriver[0] != 0); /* Should already have been explicitly set by the Wayland check above */
      if (
        (sdl_videodriver[0] != 'W' && sdl_videodriver[0] != 'w')
          || (sdl_videodriver[1] != 'A' && sdl_videodriver[1] != 'a')
          || (sdl_videodriver[2] != 'Y' && sdl_videodriver[2] != 'y')
          || (sdl_videodriver[3] != 'L' && sdl_videodriver[3] != 'l')
          || (sdl_videodriver[4] != 'A' && sdl_videodriver[4] != 'a')
          || (sdl_videodriver[5] != 'N' && sdl_videodriver[5] != 'n')
          || (sdl_videodriver[6] != 'D' && sdl_videodriver[6] != 'd')
          || sdl_videodriver[7] != 0
      ) {
        mkxp_setenv("WAYLAND_DISPLAY", nullptr);
      }
    }
#endif // MKXPZ_CHECK_FOR_WAYLAND_SUPPORT

#ifdef MKXPZ_HAVE_ANGLE
    bool angle_allow_fallback = false;
    {
      const char *angle_default_platform = getenv("ANGLE_DEFAULT_PLATFORM");
      switch (conf.renderer) {
        default:
          angle_allow_fallback = true;
          if (angle_default_platform == nullptr || angle_default_platform[0] == 0) {
#  ifdef MKXPZ_HAVE_ANGLE_METAL
            mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "metal");
#  elif !defined(MKXPZ_HAVE_ANGLE_DIRECT3D9) && !defined(MKXPZ_HAVE_ANGLE_DIRECT3D11)
#    ifdef MKXPZ_HAVE_ANGLE_VULKAN
#      ifdef MKXPZ_CHECK_FOR_LAVAPIPE
            /* Check if ANGLE's Vulkan backend would use LLVMpipe. If so, use OpenGL instead. */
            mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "gl");
            VkResult result = volkInitialize();
            VkInstance instance;
            uint32_t physicalDeviceCount;
            std::vector<VkPhysicalDevice> physicalDevices;
            if (result == VK_SUCCESS) {
              static const VkApplicationInfo applicationInfo {
                /*sType=*/VK_STRUCTURE_TYPE_APPLICATION_INFO,
                /*pNext=*/nullptr,
                /*pApplicationName=*/"",
                /*applicationVersion=*/0,
                /*pEngineName=*/"",
                /*engineVersion=*/0,
                /*apiVersion=*/VK_API_VERSION_1_0,
              };
              static const VkInstanceCreateInfo instanceCreateInfo {
                /*sType=*/VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
                /*pNext=*/nullptr,
                /*flags=*/0,
                /*pApplicationInfo=*/&applicationInfo,
                /*enabledLayerCount=*/0,
                /*ppEnabledLayerNames=*/nullptr,
                /*enabledExtensionCount=*/0,
                /*ppEnabledExtensionNames=*/nullptr,
              };
              result = vkCreateInstance(&instanceCreateInfo, nullptr, &instance);
            }
            if (result == VK_SUCCESS) {
              volkLoadInstance(instance);
              result = vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, nullptr);
              if (result == VK_SUCCESS) {
                physicalDevices.resize(physicalDeviceCount);
                result = vkEnumeratePhysicalDevices(instance, &physicalDeviceCount, physicalDevices.data());
              }
              if (result == VK_SUCCESS && !physicalDevices.empty()) {
                VkPhysicalDeviceProperties physicalDeviceProperties;
                VkPhysicalDevice preferredPhysicalDevice = physicalDevices[0];
                const char *anglePreferredDevice = getenv("ANGLE_PREFERRED_DEVICE");
                if (anglePreferredDevice == nullptr) {
                  anglePreferredDevice = "";
                }
                for (VkPhysicalDevice physicalDevice : physicalDevices) {
                  vkGetPhysicalDeviceProperties(physicalDevice, &physicalDeviceProperties);
                  if (std::strcmp(physicalDeviceProperties.deviceName, anglePreferredDevice) == 0) {
                    preferredPhysicalDevice = physicalDevice;
                    break;
                  }
                }
                vkGetPhysicalDeviceProperties(preferredPhysicalDevice, &physicalDeviceProperties);
                if (std::strncmp(physicalDeviceProperties.deviceName, "llvmpipe ", sizeof "llvmpipe " - 1) != 0) {
                  mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "vulkan");
                }
              }
              vkDestroyInstance(instance, nullptr);
            }
#      else
            mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "vulkan");
#      endif // MKXPZ_CHECK_FOR_LAVAPIPE
#    else
            mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "gl");
#    endif // MKXPZ_HAVE_ANGLE_VULKAN
#  endif
          }
          break;
#ifdef MKXPZ_HAVE_ANGLE_NULL
        case 1:
          mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "null");
          break;
#endif // MKXPZ_HAVE_ANGLE_NULL
        case 2:
          mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "gl");
          break;
#ifdef MKXPZ_HAVE_ANGLE_VULKAN
        case 3:
          mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "vulkan");
          break;
#endif // MKXPZ_HAVE_ANGLE_VULKAN
#ifdef MKXPZ_HAVE_ANGLE_METAL
        case 4:
          mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "metal");
          break;
#elif defined(MKXPZ_HAVE_ANGLE_DIRECT3D9) || defined(MKXPZ_HAVE_ANGLE_DIRECT3D11)
        case 4:
          mkxp_setenv("ANGLE_DEFAULT_PLATFORM", nullptr);
          break;
#elif defined(MKXPZ_HAVE_ANGLE_VULKAN)
        case 4:
          mkxp_setenv("ANGLE_DEFAULT_PLATFORM", "vulkan");
          break;
#endif // MKXPZ_HAVE_ANGLE_METAL
      }
      angle_default_platform = getenv("ANGLE_DEFAULT_PLATFORM");
      if (angle_default_platform != nullptr && std::strcmp(angle_default_platform, "gl") == 0) {
        mkxp_use_angle = false;
      }
    }

    if (mkxp_use_angle) {
      bool sdl_hint_opengl_es_driver = SDL_GetHintBoolean(SDL_HINT_OPENGL_ES_DRIVER, SDL_FALSE);
      bool sdl_hint_video_x11_force_egl = SDL_GetHintBoolean(SDL_HINT_VIDEO_X11_FORCE_EGL, SDL_FALSE);
      SDL_SetHintWithPriority(SDL_HINT_OPENGL_ES_DRIVER, "1", SDL_HINT_OVERRIDE);
      SDL_SetHintWithPriority(SDL_HINT_VIDEO_X11_FORCE_EGL, "1", SDL_HINT_OVERRIDE);
      if (angle_allow_fallback && (win = initVideo(conf)) == nullptr) {
        // Try again without ANGLE
        mkxp_use_angle = false;
        SDL_SetHintWithPriority(SDL_HINT_OPENGL_ES_DRIVER, sdl_hint_opengl_es_driver ? "1" : "0", SDL_HINT_OVERRIDE);
        SDL_SetHintWithPriority(SDL_HINT_VIDEO_X11_FORCE_EGL, sdl_hint_video_x11_force_egl ? "1" : "0", SDL_HINT_OVERRIDE);
      }
    }
#endif // MKXPZ_HAVE_ANGLE

    BOOT_MARK("main: before CreateWindow\n");
    SWITCH_TRACE("mkxp-z: before SDL_CreateWindow\n");

    if (win == nullptr && (win = initVideo(conf)) == nullptr) {
      showInitError(std::string("Error creating window: ") + SDL_GetError());
      return 0;
    }

    BOOT_MARK("main: after CreateWindow\n");
    SWITCH_TRACE("mkxp-z: after SDL_CreateWindow\n");

    if (!EventThread::allocUserEvents()) {
      printf("mkxp-z: EventThread::allocUserEvents failed\n");
      fflush(stdout);
      showInitError("Error allocating SDL user events");
      return 0;
    }

    BOOT_MARK("main: after allocUserEvents\n");
    SWITCH_TRACE("mkxp-z: after EventThread::allocUserEvents\n");

#ifdef MKXPZ_STEAM
    if (!STEAMSHIM_init()) {
      showInitError("Failed to initialize Steamworks. The application cannot "
                    "continue launching.");
      SDL_Quit();
      return 0;
    }
#endif

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
    
#ifdef __APPLE__
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
    
#ifdef __APPLE__
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

#ifdef __SWITCH__
    switch_setup_openal_debug();
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
    
#ifdef __APPLE__
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
