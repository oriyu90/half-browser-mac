#ifndef JSON_UTIL_H
#define JSON_UTIL_H
#include <string>
#include <vector>

/// Small, dependency-free JSON helpers for the flat/nested objects this app
/// persists. Values are never trusted: every reader has a default.
namespace JsonUtil {

/// Escape a string for embedding inside JSON double quotes.
std::string escape(const std::string& s);

/// Read a string field: "key":"value". Returns `fallback` when absent.
std::string getString(const std::string& json, const std::string& key, const std::string& fallback = "");

/// Read a numeric field: "key":123
long long getInt(const std::string& json, const std::string& key, long long fallback = 0);

/// Read a floating point field: "key":1.5
double getDouble(const std::string& json, const std::string& key, double fallback = 0.0);

/// Read a boolean field: "key":true
bool getBool(const std::string& json, const std::string& key, bool fallback = false);

/// True when the object contains the key at all.
bool hasKey(const std::string& json, const std::string& key);

/// Extract every object `{...}` found inside the array under `key`
/// (or every top-level object when `key` is empty). Nested objects are not
/// supported — the app's persisted records are flat.
std::vector<std::string> getObjectArray(const std::string& json, const std::string& key = "");

/// Minimal percent-decoding used for JS -> native console messages.
std::string urlDecode(const std::string& s);

/// Percent-encode a string for use in a URL query or JS message.
std::string urlEncode(const std::string& s);

}  // namespace JsonUtil

#endif
