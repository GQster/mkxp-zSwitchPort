#ifndef SWITCH_ASSERT_WRAPPER_H
#define SWITCH_ASSERT_WRAPPER_H

#ifdef __SWITCH__

#ifdef __cplusplus
extern "C" {
#endif

extern void __assert_func(const char *, int, const char *, const char *) __attribute__((__noreturn__));

#ifdef __cplusplus
}
#endif

#undef assert
#define assert(e) ((e) ? (void)0 : __assert_func(__FILE__, __LINE__, __func__, #e))

#endif

#endif