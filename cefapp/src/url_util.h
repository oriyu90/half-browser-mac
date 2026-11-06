#ifndef URL_UTIL_H
#define URL_UTIL_H
#include <string>

/// URL helpers mirroring the Android `UrlNormalizer` contract.
namespace UrlUtil {

/// Validate an http(s) URL. Returns the normalised URL, or "" when invalid.
std::string validateWebUrl(const std::string& url);

/// Stable identity for "same page" checks (lower-case host, no default port,
/// no trailing slash). Returns "" when invalid.
std::string canonicalForCompare(const std::string& url);

/// Host part of a valid web URL ("" when invalid).
std::string displayHost(const std::string& url);

/// Turn address-bar input into a URL to load ("" when it must be rejected).
/// `searchTemplate` contains a %s placeholder.
std::string toNavigable(const std::string& input, const std::string& searchTemplate);

/// URL for a search query.
std::string searchUrl(const std::string& query, const std::string& searchTemplate);

/// Scheme of a URL, lower-case ("" when absent).
std::string scheme(const std::string& url);

/// Origin of a URL (scheme://host[:port]), "" when invalid.
std::string origin(const std::string& url);

}  // namespace UrlUtil

#endif
