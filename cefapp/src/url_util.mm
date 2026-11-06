#include "url_util.h"
#include "json_util.h"
#include <algorithm>
#include <cctype>
#include <regex>

namespace {

std::string toLower(std::string s) {
    std::transform(s.begin(), s.end(), s.begin(), [](unsigned char c) { return (char)tolower(c); });
    return s;
}

struct Parts {
    std::string scheme;
    std::string host;
    int port = -1;          // -1 = unspecified
    std::string path;
    std::string query;      // without '?'
    bool hasQuery = false;
    bool valid = false;
};

Parts parse(const std::string& url) {
    Parts p;
    std::string s = url;
    // Trim surrounding whitespace.
    size_t b = s.find_first_not_of(" \t\r\n");
    size_t e = s.find_last_not_of(" \t\r\n");
    if (b == std::string::npos) return p;
    s = s.substr(b, e - b + 1);

    size_t schemeEnd = s.find("://");
    if (schemeEnd == std::string::npos) return p;
    p.scheme = toLower(s.substr(0, schemeEnd));
    if (p.scheme != "http" && p.scheme != "https") return p;

    std::string rest = s.substr(schemeEnd + 3);
    // Strip userinfo (rejected by Android; we refuse it too).
    size_t at = rest.find('@');
    size_t slash = rest.find_first_of("/?#");
    if (at != std::string::npos && (slash == std::string::npos || at < slash)) return p;

    std::string authority = (slash == std::string::npos) ? rest : rest.substr(0, slash);
    std::string tail = (slash == std::string::npos) ? "" : rest.substr(slash);

    if (authority.empty()) return p;
    size_t colon = authority.rfind(':');
    if (colon != std::string::npos) {
        std::string portStr = authority.substr(colon + 1);
        if (!portStr.empty()) {
            bool digits = std::all_of(portStr.begin(), portStr.end(), [](unsigned char c) { return isdigit(c); });
            if (!digits) return p;
            int v = std::stoi(portStr);
            if (v <= 0 || v > 65535) return p;
            p.port = v;
        }
        authority = authority.substr(0, colon);
    }
    p.host = toLower(authority);
    if (p.host.empty()) return p;

    size_t q = tail.find('?');
    if (q != std::string::npos) {
        p.path = tail.substr(0, q);
        p.query = tail.substr(q + 1);
        p.hasQuery = true;
    } else {
        p.path = tail;
    }
    size_t hash = p.path.find('#');
    if (hash != std::string::npos) p.path = p.path.substr(0, hash);
    if (p.query.find('#') != std::string::npos) p.query = p.query.substr(0, p.query.find('#'));

    p.valid = true;
    return p;
}

}  // namespace

namespace UrlUtil {

std::string validateWebUrl(const std::string& url) {
    Parts p = parse(url);
    if (!p.valid) return "";
    std::string out = p.scheme + "://" + p.host;
    if (p.port > 0) out += ":" + std::to_string(p.port);
    out += p.path.empty() ? "/" : p.path;
    if (p.hasQuery) out += "?" + p.query;
    return out;
}

std::string canonicalForCompare(const std::string& url) {
    Parts p = parse(url);
    if (!p.valid) return "";
    bool defaultPort = (p.scheme == "https" && p.port == 443) || (p.scheme == "http" && p.port == 80);
    std::string out = p.scheme + "://" + p.host;
    if (p.port > 0 && !defaultPort) out += ":" + std::to_string(p.port);
    std::string path = p.path;
    if (path.empty()) path = "/";
    if (path.size() > 1 && path.back() == '/') path.pop_back();
    out += path;
    if (p.hasQuery) out += "?" + p.query;
    return out;
}

std::string displayHost(const std::string& url) {
    Parts p = parse(url);
    return p.valid ? p.host : "";
}

std::string scheme(const std::string& url) {
    size_t k = url.find("://");
    if (k == std::string::npos) return "";
    return toLower(url.substr(0, k));
}

std::string origin(const std::string& url) {
    Parts p = parse(url);
    if (!p.valid) return "";
    std::string out = p.scheme + "://" + p.host;
    if (p.port > 0) out += ":" + std::to_string(p.port);
    return out;
}

std::string searchUrl(const std::string& query, const std::string& searchTemplate) {
    std::string encoded = JsonUtil::urlEncode(query);
    std::string out = searchTemplate;
    size_t pos = out.find("%s");
    if (pos != std::string::npos) out.replace(pos, 2, encoded);
    return out;
}

std::string toNavigable(const std::string& input, const std::string& searchTemplate) {
    // Trim.
    size_t b = input.find_first_not_of(" \t\r\n");
    size_t e = input.find_last_not_of(" \t\r\n");
    if (b == std::string::npos) return "";
    std::string trimmed = input.substr(b, e - b + 1);

    if (trimmed.find(' ') != std::string::npos) {
        return searchUrl(trimmed, searchTemplate);
    }

    // Host-like input ("example.com", "192.168.0.165:8844", "localhost:8080/x").
    static const std::regex hostLike(
        "^(localhost|\\d{1,3}(\\.\\d{1,3}){3}|[a-z0-9]([a-z0-9-]*[a-z0-9])?(\\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)+)(:\\d{1,5})?([/?#].*)?$",
        std::regex::icase);
    if (std::regex_match(trimmed, hostLike)) {
        return validateWebUrl("https://" + trimmed);
    }

    static const std::regex schemeRe("^([a-zA-Z][a-zA-Z0-9+.-]*):");
    std::smatch m;
    if (std::regex_search(trimmed, m, schemeRe)) {
        std::string s = toLower(m[1].str());
        if (s != "http" && s != "https") return "";  // never run javascript:, file:, intent:
        return validateWebUrl(trimmed);
    }

    return searchUrl(trimmed, searchTemplate);
}

}  // namespace UrlUtil
