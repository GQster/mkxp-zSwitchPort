# ──────────────────────────────────────────────────────────────
# 🕹️ Nintendo Switch: Override all dependencies FIRST
# ──────────────────────────────────────────────────────────────
if host_system == 'switch'
    message('🎮 Configuring mkxp-z for Nintendo Switch...')
    
    # Common Switch include directories
    switch_inc = include_directories(
        '/opt/devkitpro/libnx/include',
        '/opt/devkitpro/portlibs/switch/include'
    )
    
    switch_link_args = [
        '-L/opt/devkitpro/portlibs/switch/lib',
        '-L/opt/devkitpro/libnx/lib'
    ]

    # Override PhysFS (we built this statically)
    physfs = declare_dependency(
        include_directories: include_directories('libs/physfs-switch/include'),
        link_args: [join_paths(meson.project_source_root(), 'libs/physfs-switch/lib/libphysfs.a')]
    )
    
    # OpenAL from devkitPro portlibs
    openal = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lopenal']
    )
    
    # Theora
    theora = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-ltheora']
    )
    
    # Vorbis
    vorbisfile = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lvorbisfile']
    )
    
    vorbis = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lvorbis']
    )
    
    # Ogg
    ogg = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-logg']
    )
    
    # SDL2
    sdl2 = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lSDL2', '-lnx', '-lglapi', '-ldrm_nouveau', '-lm']
    )
    
    # SDL_sound (our custom build)
    sdl_sound = declare_dependency(
        include_directories: include_directories('libs/SDL_sound-switch/include'),
        link_args: [join_paths(meson.project_source_root(), 'libs/SDL_sound-switch/lib/libSDL2_sound.a')]
    )
    
    # SDL2_ttf
    sdl2_ttf = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lSDL2_ttf', '-lfreetype']
    )
    
    # FreeType
    freetype = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lfreetype']
    )
    
    # Pixman
    pixman = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lpixman-1']
    )
    
    # PNG
    png = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lpng16']
    )
    
    # zlib
    zlib = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lz']
    )
    
    # uchardet
    uchardet = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-luchardet']
    )
    
    # SDL2_image
    sdl2_image = declare_dependency(
        include_directories: switch_inc,
        link_args: switch_link_args + ['-lSDL2_image', '-ljpeg', '-lpng16', '-lwebp']
    )
    
    # bzip2
    bz2 = declare_dependency(
        link_args: switch_link_args + ['-lbz2']
    )
    
    # iconv (provided by libnx)
    iconv = declare_dependency(
        link_args: ['-lnx']
    )
    
    # charset (not needed on Switch, libnx handles it)
    # We skip the charset library lookup entirely
    
    # Ruby (our custom static build)
    ruby = declare_dependency(
        include_directories: include_directories(
            'libs/ruby-switch/include/ruby-3.2.0',
            'libs/ruby-switch/include/ruby-3.2.0/aarch64-linux'
        ),
        link_args: [
            join_paths(meson.project_source_root(), 'libs/ruby-switch/lib/libruby-static.a'),
            '-lm',
            '-lpthread'
        ]
    )
    global_dependencies += ruby

else
    # ──────────────────────────────────────────────────────────────
    # Original dependency discovery for non-Switch platforms
    # ──────────────────────────────────────────────────────────────
physfs = dependency('physfs', version: '>=2.1', static: build_static)
openal = dependency('openal', static: build_static, method: 'pkg-config')
theora = dependency('theora', static: build_static)
vorbisfile = dependency('vorbisfile', static: build_static)
vorbis = dependency('vorbis', static: build_static)
ogg = dependency('ogg', static: build_static)
sdl2 = dependency('SDL2', static: build_static)
    sdl_sound = compilers['cpp'].find_library('SDL2_sound')
sdl2_ttf = dependency('SDL2_ttf', static: build_static)
freetype = dependency('freetype2', static: build_static)
pixman = dependency('pixman-1', static: build_static)
png = dependency('libpng', static: build_static)
zlib = dependency('zlib', static: build_static)
uchardet = dependency('uchardet', static: build_static)

# As no pkg-config file is generated for static sdl2_image, and pkg-config is
# the default option for meson detecting dependencies, pkg-config will fail to
# find sdl2_image.pc in the build's lib/pkgconfig folder and instead pull it
# from the locally installed packages if it exists.
# To work around this, we first check to see if cmake can find our sdl2_image
# sub project and use that, then check using pkg-config as normal if we are not
# building the sub project.
# It looks like upstream SDL_image fixed this for SDL3, so we can hopefully
# remove this workaround after eventually upgrading to SDL3.
sdl2_image = dependency('SDL2_image', modules: ['SDL2_image::SDL2_image-static', 'SDL2_image::brotlidec-static', 'SDL2_image::brotlicommon-static', 'SDL2_image::hwy', 'SDL2_image::jxl_dec-static'], static: build_static, method: 'cmake', required: false)
if sdl2_image.found() == false
    sdl2_image = dependency('SDL2_image', modules: ['SDL2_image::SDL2_image-static', 'SDL2_image::brotlidec-static', 'SDL2_image::brotlicommon-static', 'SDL2_image::hwy', 'SDL2_image::jxl_dec-static'], static: build_static)
endif

if host_system == 'windows'
    bz2 = dependency('bzip2', static: build_static)
    iconv = compilers['cpp'].find_library('iconv', static: build_static)
else
    bz2 = compilers['cpp'].find_library('bz2')
    # FIXME: Specifically asking for static doesn't work if iconv isn't
    # installed in the system prefix somewhere
    iconv = compilers['cpp'].find_library('iconv')
    global_dependencies += compilers['cpp'].find_library('charset')
endif

# If OpenSSL is present, you get HTTPS support
if get_option('enable-https') == true
    if host_system == 'switch'
        # OpenSSL on Switch
        openssl = declare_dependency(
            include_directories: include_directories('/opt/devkitpro/portlibs/switch/include'),
            link_args: ['-L/opt/devkitpro/portlibs/switch/lib', '-lssl', '-lcrypto']
        )
        global_dependencies += openssl
        global_args += '-DMKXPZ_SSL'
    else
        openssl = dependency('openssl', required: false, static: build_static)
        if openssl.found() == true
            global_dependencies += openssl
            global_args += '-DMKXPZ_SSL'
            if host_system == 'windows'
                global_link_args += '-lcrypt32'
            endif
        else
            warning('Could not locate OpenSSL. HTTPS will be disabled.')
        endif
    endif
endif

# Windows needs to be treated like a special needs child here
explicit_libs = ''
if host_system == 'windows'
    # Newer versions of Ruby will refuse to link without these
    explicit_libs += 'libmsvcrt;libgcc;libmingwex;libgmp;'
endif
if build_static == true
    if host_system == 'windows'
        # '-static-libgcc', '-static-libstdc++' are here to avoid needing to ship a separate libgcc_s_seh-1.dll on Windows; it still works without those flags if you have the dll.
        global_link_args += ['-static-libgcc', '-static-libstdc++', '-Wl,-Bstatic', '-lgcc', '-lstdc++', '-lpthread', '-Wl,-Bdynamic']
    else
        global_link_args += ['-static-libgcc', '-static-libstdc++']
    endif
    global_args += '-DAL_LIBTYPE_STATIC'
endif

foreach l : explicit_libs.split(';')
        if l != ''
            global_link_args += '-l:' + l + '.a'
        endif
endforeach

alcdev_struct = 'ALCdevice_struct'
if openal.type_name() == 'pkgconfig'
    if openal.version().version_compare('>=1.20.1')
        alcdev_struct = 'ALCdevice'
    endif
endif

global_args += '-DMKXPZ_ALCDEVICE=' + alcdev_struct


global_include_dirs += include_directories('.',
    'audio',
    'crypto',
    'display', 'display/gl', 'display/libnsgif', 'display/libnsgif/utils',
    'etc',
    'filesystem', 'filesystem/ghc',
    'input',
    'net',
    'system',
    'util', 'util/sigslot', 'util/sigslot/adapter'
)

global_dependencies += [openal, zlib, bz2, sdl2, sdl_sound, pixman, physfs, theora, vorbisfile, vorbis, ogg, sdl2_ttf, freetype, sdl2_image, png, iconv, uchardet]
if host_system == 'windows'
    global_dependencies += compilers['cpp'].find_library('wsock32')
endif

if get_option('shared_fluid') == true
    if host_system == 'switch'
        warning('FluidSynth is not supported on Nintendo Switch. Disabling.')
    else
        fluidsynth = dependency('fluidsynth', static: build_static)
        add_project_arguments('-DSHARED_FLUID', language: 'cpp')
        global_dependencies += fluidsynth
        if host_system == 'windows'
            global_dependencies += compilers['cpp'].find_library('dsound')
        endif
    endif
endif

if get_option('cjk_fallback_font') == true
    add_project_arguments('-DMKXPZ_CJK_FONT', language: 'cpp')
endif

main_source = files(
    'main.cpp',
    'config.cpp',
    'eventthread.cpp',
    'settingsmenu.cpp',
    'sharedstate.cpp',
    
    'audio/alstream.cpp',
    'audio/audio.cpp',
    'audio/audiostream.cpp',
    'audio/fluid-fun.cpp',
    'audio/midisource.cpp',
    'audio/sdlsoundsource.cpp',
    'audio/soundemitter.cpp',
    'audio/vorbissource.cpp',
    'theoraplay/theoraplay.c',

    'crypto/rgssad.cpp',

    'display/autotiles.cpp',
    'display/autotilesvx.cpp',
    'display/bitmap.cpp',
    'display/font.cpp',
    'display/graphics.cpp',
    'display/plane.cpp',
    'display/sprite.cpp',
    'display/tilemap.cpp',
    'display/tilemapvx.cpp',
    'display/viewport.cpp',
    'display/window.cpp',
    'display/windowvx.cpp',

    'display/libnsgif/libnsgif.c',
    'display/libnsgif/lzw.c',

    'display/gl/gl-debug.cpp',
    'display/gl/gl-fun.cpp',
    'display/gl/gl-meta.cpp',
    'display/gl/glstate.cpp',
    'display/gl/scene.cpp',
    'display/gl/shader.cpp',
    'display/gl/texpool.cpp',
    'display/gl/tileatlas.cpp',
    'display/gl/tileatlasvx.cpp',
    'display/gl/tilequad.cpp',
    'display/gl/vertex.cpp',

    'util/iniconfig.cpp',
    'util/win-consoleutils.cpp',
    
    'etc/etc.cpp',
    'etc/table.cpp',

    'filesystem/filesystem.cpp',
    'filesystem/filesystemImpl.cpp',
    
    'input/input.cpp',
    'input/keybindings.cpp',

    'net/LUrlParser.cpp',
    'net/net.cpp',

    'system/systemImpl.cpp'
)

global_sources += main_source

# ──────────────────────────────────────────────────────────────
# 🕹️ Nintendo Switch platform support
# ──────────────────────────────────────────────────────────────
if host_system == 'switch'
    switch_dir = meson.project_source_root() / 'switch'
    switch_sources = files(
        switch_dir / 'switch_main.cpp',
        switch_dir / 'SwitchFilesystem.cpp',
        switch_dir / 'SwitchInput.cpp',
    )
    global_sources += switch_sources
    
    # Additional Switch-specific compile flags
    global_args += [
        '-D__SWITCH__',
        '-DMKXP_BACKEND_GLES2',
        '-Dunix'
    ]

    # Link against libnx
    global_link_args += ['-lnx', '-lm']
endif