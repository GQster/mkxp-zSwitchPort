# ──────────────────────────────────────────────────────────────
# 🕹️ Nintendo Switch: Override all dependencies FIRST
# ──────────────────────────────────────────────────────────────
if host_system == 'switch'
    global_args += '-D__SWITCH__' 
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
        include_directories: include_directories('../libs/physfs-switch/include'),
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
        include_directories: include_directories('../libs/SDL_sound-switch/include'),
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
        include_directories: [
            switch_inc,
            include_directories('/opt/devkitpro/portlibs/switch/include')  # Explicit
        ],
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
            '../libs/ruby-switch/include/ruby-3.2.0',
            '../libs/ruby-switch/include/ruby-3.2.0/aarch64-elf'
        ),
        link_args: [
            join_paths(meson.project_source_root(), 'libs/ruby-switch/lib/libruby-static.a'),
            '-lm',
            '-lpthread'
        ]
    )
    global_dependencies += ruby
    global_dependencies += [
        physfs, openal, theora, vorbisfile, vorbis, ogg, sdl2, sdl_sound,
        sdl2_ttf, freetype, pixman, png, zlib, uchardet, sdl2_image, bz2, iconv
    ]

else
endif

if get_option('cjk_fallback_font') == true
    add_project_arguments('-DMKXPZ_CJK_FONT', language: 'cpp')
endif

global_include_dirs += include_directories('.', 'util', 'display', 'audio', 'filesystem', 'input', 'net', 'system', 'etc', 'crypto', 'theoraplay', 'display/gl')
global_include_dirs += include_directories('/opt/devkitpro/portlibs/switch/include/AL')
global_include_dirs += include_directories('/opt/devkitpro/portlibs/switch/include/pixman-1')
global_include_dirs += include_directories('/opt/devkitpro/portlibs/switch/include/AL')
global_include_dirs += include_directories('/opt/devkitpro/portlibs/switch/include/SDL2')
global_include_dirs += include_directories('/opt/devkitpro/portlibs/switch/include/AL')
global_include_dirs += include_directories('/opt/devkitpro/portlibs/switch/include/pixman-1')
global_include_dirs += include_directories('/opt/devkitpro/portlibs/switch/include/AL')
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
    global_args += '-D__SWITCH__' 
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
endif  # End of host_system == switch (first block)
