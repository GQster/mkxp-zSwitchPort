#ifndef SWITCH_ASSERT_H
#define SWITCH_ASSERT_H
#ifdef __SWITCH__
#include <assert.h>
#ifndef assert
#ifdef NDEBUG
#define assert(x) ((void)0)
#else
extern void __assert_func(const char *, int, const char *, const char *);
#define assert(e) ((e) ? (void)0 : __assert_func(__FILE__, __LINE__, __func__, #e))
#endif
#endif
#endif
#endif
