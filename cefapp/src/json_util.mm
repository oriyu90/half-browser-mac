#include "json_util.h"
#include <cctype>
#include <cstdlib>

namespace JsonUtil {

std::string escape(const std::string& s) {
    std::string out;
    out.reserve(s.size() + 8);
    for (unsigned char c : s) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (c < 0x20) {
                    char buf[8];
                    snprintf(buf, sizeof(buf), "\\u%04x", c);
                    out += buf;
                } else {
                    out += (char)c;
                }
        }
    }
    return out;
}

bool hasKey(const std::string& json, const std::string& key) {
    return json.find("\"" + key + "\":") != std::string::npos;
}

std::string getString(const std::string& json, const std::string& key, const std::string& fallback) {
    const std::string needle = "\"" + key + "\":\"";
    size_t p = json.find(needle);
    if (p == std::string::npos) return fallback;
    p += needle.size();
    std::string out;
    for (size_t i = p; i < json.size(); ++i) {
        char c = json[i];
        if (c == '\\' && i + 1 < json.size()) {
            char n = json[++i];
            switch (n) {
                case 'n': out += '\n'; break;
                case 'r': out += '\r'; break;
                case 't': out += '\t'; break;
                case '"': out += '"'; break;
                case '\\': out += '\\'; break;
                case '/': out += '/'; break;
                default: out += n; break;
            }
            continue;
        }
        if (c == '"') return out;
        out += c;
    }
    return fallback;
}

namespace {
// Locate the raw token after "key": (number or literal).
bool rawToken(const std::string& json, const std::string& key, std::string& out) {
    size_t p = json.find("\"" + key + "\":");
    if (p == std::string::npos) return false;
    p += key.size() + 3;
    while (p < json.size() && (json[p] == ' ' || json[p] == '\t' || json[p] == '\n')) ++p;
    if (p >= json.size()) return false;
    size_t e = p;
    while (e < json.size()) {
        char c = json[e];
        if (c == ',' || c == '}' || c == ']' || c == ' ' || c == '\n' || c == '\t') break;
        ++e;
    }
    out = json.substr(p, e - p);
    return !out.empty();
}
}  // namespace

long long getInt(const std::string& json, const std::string& key, long long fallback) {
    std::string tok;
    if (!rawToken(json, key, tok)) return fallback;
    char* end = nullptr;
    long long v = strtoll(tok.c_str(), &end, 10);
    if (end == tok.c_str()) return fallback;
    return v;
}

double getDouble(const std::string& json, const std::string& key, double fallback) {
    std::string tok;
    if (!rawToken(json, key, tok)) return fallback;
    char* end = nullptr;
    double v = strtod(tok.c_str(), &end);
    if (end == tok.c_str()) return fallback;
    return v;
}

bool getBool(const std::string& json, const std::string& key, bool fallback) {
    std::string tok;
    if (!rawToken(json, key, tok)) return fallback;
    if (tok == "true") return true;
    if (tok == "false") return false;
    return fallback;
}

std::vector<std::string> getObjectArray(const std::string& json, const std::string& key) {
    std::vector<std::string> out;
    size_t start = 0;
    if (!key.empty()) {
        size_t k = json.find("\"" + key + "\":[");
        if (k == std::string::npos) return out;
        start = k + key.size() + 4;
    } else {
        start = json.find('[');
        if (start == std::string::npos) return out;
        start += 1;
    }

    int depth = 0;
    size_t objStart = std::string::npos;
    for (size_t i = start; i < json.size(); ++i) {
        char c = json[i];
        if (c == '"') {
            // Skip string contents so braces inside strings do not count.
            ++i;
            while (i < json.size()) {
                if (json[i] == '\\') { i += 2; continue; }
                if (json[i] == '"') break;
                ++i;
            }
            continue;
        }
        if (c == '{') {
            if (depth == 0) objStart = i;
            ++depth;
        } else if (c == '}') {
            --depth;
            if (depth == 0 && objStart != std::string::npos) {
                out.push_back(json.substr(objStart, i - objStart + 1));
                objStart = std::string::npos;
            }
        } else if (c == ']' && depth == 0) {
            break;
        }
    }
    return out;
}

std::string urlDecode(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%' && i + 2 < s.size() && isxdigit((unsigned char)s[i + 1]) && isxdigit((unsigned char)s[i + 2])) {
            out += (char)std::stoi(s.substr(i + 1, 2), nullptr, 16);
            i += 2;
        } else if (s[i] == '+') {
            out += ' ';
        } else {
            out += s[i];
        }
    }
    return out;
}

std::string urlEncode(const std::string& s) {
    static const char* hex = "0123456789ABCDEF";
    std::string out;
    for (unsigned char c : s) {
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') {
            out += (char)c;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 0xF];
        }
    }
    return out;
}

}  // namespace JsonUtil
