#ifdef __SWITCH__
#include <stdlib.h>
#include <string.h>

typedef void* iconv_t;

iconv_t libiconv_open(const char* tocode, const char* fromcode) {
    (void)tocode; (void)fromcode;
    return (iconv_t)1; // Return non-null to indicate "success"
}

size_t libiconv(iconv_t cd, char** inbuf, size_t* inbytesleft, 
                char** outbuf, size_t* outbytesleft) {
    (void)cd;
    // Simple pass-through: copy input to output
    if (inbuf && *inbuf && outbuf && *outbuf && inbytesleft && outbytesleft) {
        size_t to_copy = (*inbytesleft < *outbytesleft) ? *inbytesleft : *outbytesleft;
        memcpy(*outbuf, *inbuf, to_copy);
        *inbuf += to_copy;
        *outbuf += to_copy;
        *inbytesleft -= to_copy;
        *outbytesleft -= to_copy;
    }
    return 0; // Success
}

int libiconv_close(iconv_t cd) {
    (void)cd;
    return 0; // Success
}
#endif
