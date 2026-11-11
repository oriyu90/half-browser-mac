// Minimal self-check for UrlUtil (run with --self-test).
#include "url_util.h"
#include "json_util.h"
#include "bookmarks.h"
#include "localization.h"
#include "half_browser_core.h"
#include <algorithm>
#include <iterator>
#include <set>
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

    // Localization parity: the two catalogs must define exactly the same keys,
    // and no value may be empty. This is the machine-checked guarantee behind
    // "Japanese and English are both fully supported".
    {
        auto en = Localization::englishKeys();
        auto ja = Localization::japaneseKeys();
        expectTrue(en.size() > 200, "english catalog is populated");
        expectTrue(en.size() == ja.size(), "catalog sizes match");

        std::set<std::string> enSet(en.begin(), en.end());
        std::set<std::string> jaSet(ja.begin(), ja.end());
        std::vector<std::string> onlyEn;
        std::vector<std::string> onlyJa;
        std::set_difference(enSet.begin(), enSet.end(), jaSet.begin(), jaSet.end(),
                            std::back_inserter(onlyEn));
        std::set_difference(jaSet.begin(), jaSet.end(), enSet.begin(), enSet.end(),
                            std::back_inserter(onlyJa));
        if (!onlyEn.empty()) printf("  en-only keys: %s\n", onlyEn.front().c_str());
        if (!onlyJa.empty()) printf("  ja-only keys: %s\n", onlyJa.front().c_str());
        expectTrue(onlyEn.empty(), "no English-only keys");
        expectTrue(onlyJa.empty(), "no Japanese-only keys");

        // No empty translations in either language.
        Localization::instance().setLanguage("en");
        int emptyEn = 0;
        for (const auto& k : en) {
            if (Localization::instance().get(k).empty()) emptyEn++;
        }
        Localization::instance().setLanguage("ja");
        int emptyJa = 0;
        for (const auto& k : ja) {
            if (Localization::instance().get(k).empty()) emptyJa++;
        }
        expectEq(std::to_string(emptyEn), "0", "no empty English values");
        expectEq(std::to_string(emptyJa), "0", "no empty Japanese values");
    }

    Localization::instance().setLanguage("ja");
    const char* keys[] = {"app.name", "menu.settings", "ssl.title", "auth.title",
                          "perm.allow", "bookmark.save", "settings.title", "backup.export_ok",
                          "vpn.mac_limitation", "vpn.err.empty", "jsdialog.alert_title",
                          "download.done_title", "history.title", "watch.title"};
    for (const char* k : keys) {
        expectTrue(Localization::instance().get(k) != k, k);
    }
    Localization::instance().setLanguage("en");
    expectEq(Localization::instance().get("app.name"), "Half-Browser", "english app name");

    // ---- Rust core rules reachable through the C FFI -----------------------
    {
        // A valid config parses; an invalid one reports a code.
        const char* good =
            "[Interface]\nPrivateKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=\n"
            "Address = 10.0.0.2/32\n\n[Peer]\n"
            "PublicKey = ERERERERERERERERERERERERERERERERERERERERERE=\n"
            "Endpoint = vpn.example.com:51820\nAllowedIPs = 0.0.0.0/0\n";
        char* ep = nullptr;
        char* detail = nullptr;
        expectEq(std::to_string(hb_vpn_parse(good, &ep, &detail)), "0", "vpn parse ok");
        expectTrue(ep && std::string(ep) == "vpn.example.com:51820", "vpn endpoint");
        if (ep) hb_free_string(ep);
        if (detail) hb_free_string(detail);

        ep = nullptr;
        detail = nullptr;
        expectTrue(hb_vpn_parse("", &ep, &detail) > 0, "vpn parse rejects empty");
        if (ep) hb_free_string(ep);
        if (detail) hb_free_string(detail);

        char* tuned = hb_vpn_tune(good, 25);
        expectTrue(tuned && std::string(tuned).find("PersistentKeepalive = 25") != std::string::npos,
                   "vpn tuning keepalive");
        expectTrue(tuned && std::string(tuned).find("MTU = 1280") != std::string::npos,
                   "vpn tuning mtu");
        if (tuned) hb_free_string(tuned);

        // classify: no handshake past the grace -> Unreachable(4)
        expectEq(std::to_string(hb_vpn_classify(1000000, 0, 1060000, 0)), "4", "vpn classify unreachable");
        expectEq(std::to_string(hb_vpn_classify(1000000, 0, 1001000, 0)), "1", "vpn classify verifying");
        expectEq(std::to_string(hb_vpn_classify(1000000, 1001000, 1005000, 0)), "2", "vpn classify healthy");

        // poll schedule
        expectEq(std::to_string(hb_vpn_next_poll_delay(true, 2, 99)), "10000", "poll foreground");
        expectEq(std::to_string(hb_vpn_next_poll_delay(false, 2, 1)), "90000", "poll backoff");
        expectEq(std::to_string(hb_vpn_next_poll_delay(false, 3, 9)), "60000", "poll broken");

        // dialog budget
        HbDialogBudget* b = hb_dialog_budget_new();
        int allowed = 0;
        for (int i = 0; i < 20; i++) allowed += hb_dialog_budget_allow(b, 1000000 + i * 250);
        expectEq(std::to_string(allowed), "12", "dialog budget caps at 12");
        hb_dialog_budget_free(b);

        // JS guard shim is produced
        char* js = hb_js_guard_script();
        expectTrue(js && std::string(js).find("__hbJsGuardInstalled") != std::string::npos,
                   "js guard shim");
        if (js) hb_free_string(js);
    }

    if (failures == 0) {
        printf("SELFTEST OK\n");
        return 0;
    }
    printf("SELFTEST FAILED (%d)\n", failures);
    return 1;
}
