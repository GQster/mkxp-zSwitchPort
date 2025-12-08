#ifndef SWITCH_COMPAT_H
#define SWITCH_COMPAT_H
#ifdef __SWITCH__
#include <cstring>
#include <cstdlib>

// strdup is not available in C++ standard library on Switch
// Provide our own implementation
inline char* strdup(const char* s) {
    if (!s) return nullptr;
    std::size_t len = std::strlen(s) + 1;
    char* copy = (char*)std::malloc(len);
    if (copy) std::memcpy(copy, s, len);
    return copy;
}

#endif /* __SWITCH__ */
#endif /* SWITCH_COMPAT_H */
