#ifndef SWITCH_COMPAT_H
#define SWITCH_COMPAT_H
#ifdef __SWITCH__
#include <cstring>
#include <cstdlib>
#ifndef strdup
inline char* strdup(const char* s) {
    size_t len = strlen(s) + 1;
    char* copy = (char*)malloc(len);
    if (copy) memcpy(copy, s, len);
    return copy;
}
#endif
#endif
#endif
