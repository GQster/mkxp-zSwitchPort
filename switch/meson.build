# Switch platform stub implementations
switch_stub_sources = files(
  'switch_iconv_stub.c',
  'switch_getrusage_stub.c',
  'switch_http_stub.cpp',
  'switch_posix_stubs.c',
  'switch_main.cpp',
  'switch_gamepicker.cpp',
  'switch_pickerui.cpp',
  'switch_swkbd.cpp'
)

switch_inc = include_directories(
  '.',
  '../src',
  '/opt/devkitpro/libnx/include',
  '/opt/devkitpro/portlibs/switch/include',
  '/opt/devkitpro/portlibs/switch/include/SDL2'
)

# Build as a static library
switch_stubs = static_library('switch_stubs',
  switch_stub_sources,
  include_directories: switch_inc
)
