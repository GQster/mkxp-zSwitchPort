#ifndef SWITCH_ASSERT_COMPAT_H
#define SWITCH_ASSERT_COMPAT_H

#ifdef __SWITCH__
#ifdef __cplusplus
// C++ files
#include <cassert>
#ifndef assert
#include <assert.h>
extern "C" void __assert_func(const char *, int, const char *, const char *) __attribute__((__noreturn__));
#define assert(e) ((e) ? (void)0 : __assert_func(__FILE__, __LINE__, __func__, #e))
#endif
#else
// C files
#include <assert.h>
#ifndef assert
extern void __assert_func(const char *, int, const char *, const char *) __attribute__((__noreturn__));
#define assert(e) ((e) ? (void)0 : __assert_func(__FILE__, __LINE__, __func__, #e))
#endif
#endif
#endif

#endif
