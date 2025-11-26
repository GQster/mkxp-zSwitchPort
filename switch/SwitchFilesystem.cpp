#include "filesystem.h"
#include <string>

namespace mkxp {
class SwitchFilesystem : public Filesystem {
public:
    std::string resolvePath(const std::string& name) override {
        const char* prefixes[] = {
            "sdmc:/switch/mkxp-z/games/",
            "romfs:/"
        };
        for (auto& base : prefixes) {
            std::string full = std::string(base) + name;
            if (fileExists(full)) return full;
        }
        return name;
    }
};
}