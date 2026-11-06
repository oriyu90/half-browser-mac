// Minimal self-check for UrlUtil (run with --self-test).
#include "url_util.h"
#include "json_util.h"
#include "bookmarks.h"
#include "localization.h"
#include <cstdio>
#include <string>

static int failures = 0;

static void expectEq(const std::string& got, const std::string& want, const char* label) {
    if (got != want) {
        fprintf(stderr, "FAIL %s: got '%s' want '%s'\n", label, got.c_str(), want.c_str());
        ++failures;
    }
}

static void expectTrue(bool v, const char* label) {
    if (!v) {
        fprintf(stderr, "FAIL %s\n", label);
        ++failures;
    }
}

int RunSelfTests() {
    const std::string ddg = "https://duckduckgo.com/?q=%s";

    expectEq(UrlUtil::toNavigable("example.com", ddg), "https://example.com/", "host-like");
    expectEq(UrlUtil::toNavigable("javascript:alert(1)", ddg), "", "reject javascript");
    expectEq(UrlUtil::toNavigable("file:///etc/passwd", ddg), "", "reject file");
    expectEq(UrlUtil::toNavigable("intent://x#Intent;end", ddg), "", "reject intent");
    expectEq(UrlUtil::validateWebUrl("https://example.com/a/"), "https://example.com/a/", "validate");
    expectEq(UrlUtil::canonicalForCompare("https://Example.com:443/a/"), "https://example.com/a", "canonical");
    expectEq(UrlUtil::displayHost("https://example.com/x"), "example.com", "displayHost");
    expectEq(UrlUtil::origin("https://example.com:8443/x"), "https://example.com:8443", "origin");
    expectTrue(UrlUtil::toNavigable("hello world", ddg).rfind("https://duckduckgo.com/?q=hello", 0) == 0, "search");

    expectEq(JsonUtil::getString("{\"a\":\"x\\\"y\"}", "a"), "x\"y", "json string escape");
    expectEq(std::to_string(JsonUtil::getInt("{\"n\":42}", "n")), "42", "json int");
    expectTrue(JsonUtil::getBool("{\"b\":true}", "b"), "json bool");
    auto objs = JsonUtil::getObjectArray("{\"items\":[{\"a\":1},{\"a\":2}]}", "items");
    expectTrue(objs.size() == 2, "object array");

    // Localization parity: every English key must exist in Japanese.
    Localization::instance().setLanguage("ja");
    const char* keys[] = {"app.name", "menu.settings", "ssl.title", "auth.title",
                          "perm.allow", "bookmark.save", "settings.title", "backup.export_ok"};
    for (const char* k : keys) {
        expectTrue(Localization::instance().get(k) != k, k);
    }
    Localization::instance().setLanguage("en");
    expectEq(Localization::instance().get("app.name"), "Half-Browser", "english app name");

    if (failures == 0) {
        printf("SELFTEST OK\n");
        return 0;
    }
    printf("SELFTEST FAILED (%d)\n", failures);
    return 1;
}
