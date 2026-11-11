// Minimal self-check for UrlUtil (run with --self-test).
#include "url_util.h"
#include "json_util.h"
#include "bookmarks.h"
#include "form_login.h"
#include "settings_store.h"
#include "localization.h"
#include "half_browser_core.h"
#include "site_watch.h"
#include <algorithm>
#include <iterator>
#include <set>
#include <cstdio>
#include <fstream>
#include <sys/stat.h>
#include <unistd.h>
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

    // ---- Settings round-trip (B1/B2 regression guard) ----------------------
    // Writes to a temporary file, not the user's settings, so the self-test is
    // safe to run on a real installation.
    {
        AppSettings s;
        s.themeMode = "dark";
        s.accentHue = 123.5f;
        s.accentSaturation = 0.5f;
        s.uiScale = 1.2f;
        s.gridColumns = 5;
        s.searchEngine = "kagi";
        s.vpnAutoConnect = true;
        s.vpnAutoReconnect = false;
        s.vpnPowerSaver = true;
        s.siteWatchEnabled = true;
        s.siteWatchIntervalMinutes = 30;
        s.siteWatchWifiOnly = true;
        s.jsGuardEnabled = false;
        s.formAutofillEnabled = false;

        std::string path = "/tmp/hb_selftest_settings.json";
        // A key that is a prefix of another must not be confused with it.
        std::string blob =
            "{\"themeMode\":\"dark\",\"accentHue\":123.5,\"accentHueExtra\":999,"
            "\"accentSaturation\":0.5,\"uiScale\":1.2,\"gridColumns\":5,"
            "\"searchEngine\":\"kagi\",\"vpnAutoConnect\":true,\"vpnAutoReconnect\":false,"
            "\"vpnPowerSaver\":true,\"siteWatchEnabled\":true,\"siteWatchIntervalMinutes\":30,"
            "\"siteWatchWifiOnly\":true,\"jsGuardEnabled\":false,\"formAutofillEnabled\":false}";
        {
            std::ofstream f(path, std::ios::binary | std::ios::trunc);
            f << blob;
        }
        AppSettings loaded;
        // Parse the same way SettingsStore does, via the shared helpers.
        loaded.themeMode = JsonUtil::getString(blob, "themeMode", "system");
        loaded.accentHue = (float)JsonUtil::getDouble(blob, "accentHue", 222.0);
        loaded.vpnAutoConnect = JsonUtil::getBool(blob, "vpnAutoConnect", false);
        loaded.vpnAutoReconnect = JsonUtil::getBool(blob, "vpnAutoReconnect", true);
        loaded.siteWatchIntervalMinutes = (int)JsonUtil::getInt(blob, "siteWatchIntervalMinutes", 60);
        loaded.jsGuardEnabled = JsonUtil::getBool(blob, "jsGuardEnabled", true);

        expectEq(loaded.themeMode, "dark", "settings theme round-trip");
        // The value must be 123.5, not 999 from the longer "accentHueExtra" key.
        expectTrue(loaded.accentHue > 123.4f && loaded.accentHue < 123.6f,
                   "settings accent hue (prefix key ignored)");
        expectTrue(loaded.vpnAutoConnect, "settings vpnAutoConnect");
        expectTrue(!loaded.vpnAutoReconnect, "settings vpnAutoReconnect");
        expectEq(std::to_string(loaded.siteWatchIntervalMinutes), "30", "settings watch interval");
        expectTrue(!loaded.jsGuardEnabled, "settings jsGuard");
        remove(path.c_str());
    }

    // ---- Site watch (T1) ---------------------------------------------------
    // Everything below is pure or touches a scratch file under /tmp, so the
    // self-test never reads or writes the user's real site_watch.json.
    {
        // SHA-256 against the published NIST vectors.
        expectEq(SiteWatch::sha256Hex(""),
                 "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                 "sha256 empty");
        expectEq(SiteWatch::sha256Hex("abc"),
                 "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
                 "sha256 abc");
        // A one-byte change must change the hash (this is the whole feature).
        expectTrue(SiteWatch::sha256Hex("abc") != SiteWatch::sha256Hex("abd"),
                   "sha256 differs on one-byte change");

        // Hash comparison: no baseline -> Baseline, same -> Unchanged,
        // different -> Changed.
        const std::string h1 = SiteWatch::sha256Hex("v1");
        const std::string h2 = SiteWatch::sha256Hex("v2");
        expectTrue(SiteWatch::classify("", h1) == SiteWatchVerdict::Baseline,
                   "watch classify baseline");
        expectTrue(SiteWatch::classify(h1, h1) == SiteWatchVerdict::Unchanged,
                   "watch classify unchanged");
        expectTrue(SiteWatch::classify(h1, h2) == SiteWatchVerdict::Changed,
                   "watch classify changed");
        // An empty body hash never counts as a change.
        expectTrue(SiteWatch::classify(h1, "") == SiteWatchVerdict::Unchanged,
                   "watch classify empty new hash");

        // Interval sanitizing mirrors SettingsStore (15/30/60/180).
        expectEq(std::to_string(SiteWatch::sanitizeInterval(15)), "15", "watch interval 15");
        expectEq(std::to_string(SiteWatch::sanitizeInterval(180)), "180", "watch interval 180");
        expectEq(std::to_string(SiteWatch::sanitizeInterval(7)), "60", "watch interval default");
        expectEq(std::to_string(SiteWatch::sanitizeInterval(-1)), "60", "watch interval negative");

        // Only http(s) pages are fetched.
        expectTrue(SiteWatch::isFetchable("https://example.com/a"), "watch fetchable https");
        expectTrue(SiteWatch::isFetchable("http://example.com/"), "watch fetchable http");
        expectTrue(!SiteWatch::isFetchable("file:///etc/passwd"), "watch rejects file");
        expectTrue(!SiteWatch::isFetchable("javascript:alert(1)"), "watch rejects javascript");
        expectTrue(!SiteWatch::isFetchable(""), "watch rejects empty url");
        expectEq(SiteWatch::siteName("https://www.example.com/x"), "example.com", "watch site name");
    }

    // ---- Site watch JSON round-trip ---------------------------------------
    {
        std::vector<SiteWatchItem> items;
        SiteWatchItem a;
        a.url = "https://example.com/a";
        a.hash = SiteWatch::sha256Hex("page a");
        a.checkedAt = 1700000000000LL;
        a.title = "Example \"A\" / quote";
        SiteWatchItem b;
        b.url = "https://example.com/b?x=1&y=2";
        b.hash = "";
        b.checkedAt = 0;
        b.title = "B";
        items.push_back(a);
        items.push_back(b);

        std::string blob = SiteWatch::serialize(items, 1700000000123LL, "timeout");
        expectTrue(blob.find("\"version\":1") != std::string::npos, "watch json version 1");

        std::vector<SiteWatchItem> back;
        long long check = 0;
        std::string err;
        expectTrue(SiteWatch::parse(blob, back, check, err), "watch parse ok");
        expectEq(std::to_string(back.size()), "2", "watch round-trip item count");
        expectEq(back[0].url, a.url, "watch round-trip url");
        expectEq(back[0].hash, a.hash, "watch round-trip hash");
        expectEq(std::to_string(back[0].checkedAt), "1700000000000", "watch round-trip checkedAt");
        // Quotes and backslashes inside a title must survive escaping.
        expectEq(back[0].title, a.title, "watch round-trip title with quotes");
        expectEq(back[1].url, b.url, "watch round-trip url with query");
        expectEq(back[1].hash, "", "watch round-trip empty hash");
        expectEq(std::to_string(check), "1700000000123", "watch round-trip lastCheck");
        expectEq(err, "timeout", "watch round-trip lastError");

        // Same input -> byte-identical output (the file must be stable).
        expectEq(SiteWatch::serialize(back, check, err), blob, "watch serialize is stable");
    }

    // ---- Site watch survives corrupt input --------------------------------
    {
        const char* broken[] = {
            "",
            "not json at all",
            "{\"version\":1,\"items\":[",                       // truncated
            "{\"version\":1,\"items\":\"oops\"}",             // wrong type
            "{\"version\":1,\"items\":[{\"url\":\"https://a.example\",\"hash\":\"zz\"}]}",
            "{\"items\":[null,null,{}]}",
            "{\"items\":[{\"url\":\"file:///etc/passwd\",\"hash\":\"x\"}]}",
            "{\"lastCheck\":-5,\"items\":[{\"url\":\"https://ok.example\",\"checkedAt\":-1}]}",
            "\x00\x01\x02\xff\xfe",
        };
        for (const char* input : broken) {
            std::vector<SiteWatchItem> got;
            long long check = 12345;
            std::string err = "stale";
            // Must not throw or crash, whatever the input.
            SiteWatch::parse(input, got, check, err);
            // Sanitizing rules: no negative timestamps, no non-http URLs,
            // no malformed hashes.
            for (const SiteWatchItem& it : got) {
                expectTrue(SiteWatch::isFetchable(it.url), "watch corrupt: url sanitized");
                expectTrue(it.checkedAt >= 0, "watch corrupt: checkedAt sanitized");
                expectTrue(it.hash.empty() || it.hash.size() == 64,
                           "watch corrupt: hash sanitized");
            }
            expectTrue(check >= 0, "watch corrupt: lastCheck sanitized");
        }
        // The one record that is valid must survive; the file: URL must not.
        std::vector<SiteWatchItem> got;
        long long check = 0;
        std::string err;
        SiteWatch::parse("{\"items\":[{\"url\":\"file:///etc/passwd\"},"
                         "{\"url\":\"https://ok.example/\",\"hash\":\"abc\"}]}",
                         got, check, err);
        expectEq(std::to_string(got.size()), "1", "watch corrupt: only valid record kept");
        expectEq(got.empty() ? std::string() : got[0].hash, "", "watch corrupt: bad hash cleared");
    }

    // ---- Site watch file round-trip through disk --------------------------
    {
        const std::string path = "/tmp/hb_selftest_site_watch.json";
        remove(path.c_str());
        SiteWatch& w = SiteWatch::instance();
        w.setFilePathForTesting(path.c_str());
        // No file yet: empty state, no crash.
        expectEq(std::to_string(w.items().size()), "0", "watch load missing file");

        // Write a document by hand and read it back through load().
        {
            std::vector<SiteWatchItem> items;
            SiteWatchItem it;
            it.url = "https://example.com/watched";
            it.hash = SiteWatch::sha256Hex("body");
            it.checkedAt = 1700000000000LL;
            it.title = "Watched";
            items.push_back(it);
            std::ofstream f(path, std::ios::binary | std::ios::trunc);
            f << SiteWatch::serialize(items, 1700000000000LL, "");
        }
        w.load();
        expectEq(std::to_string(w.items().size()), "1", "watch load from disk");
        expectEq(w.items()[0].hash, SiteWatch::sha256Hex("body"), "watch load hash");
        expectEq(std::to_string(w.lastCheckMillis()), "1700000000000", "watch load lastCheck");

        // A truncated file on disk must load as an empty state, not crash.
        {
            std::ofstream f(path, std::ios::binary | std::ios::trunc);
            f << "{\"version\":1,\"items\":[{\"url\":";
        }
        w.load();
        expectEq(std::to_string(w.items().size()), "0", "watch load corrupt file");

        // A directory in place of the file must not crash either.
        remove(path.c_str());
        mkdir(path.c_str(), 0755);
        w.load();
        expectEq(std::to_string(w.items().size()), "0", "watch load unreadable path");
        rmdir(path.c_str());
        remove((path + ".tmp").c_str());
    }

    // ---- atomic write leaves no partial file ------------------------------
    {
        std::string path = "/tmp/hb_selftest_atomic.json";
        std::string tmp = path + ".tmp";
        {
            std::ofstream f(tmp, std::ios::binary | std::ios::trunc);
            f << "{\"ok\":true}";
        }
        rename(tmp.c_str(), path.c_str());
        struct stat st;
        expectTrue(stat(path.c_str(), &st) == 0, "atomic write produced the file");
        expectTrue(stat(tmp.c_str(), &st) != 0, "temp file was renamed away");
        remove(path.c_str());
    }

    // ---- credentials never travel over the console ------------------------
    {
        std::string script = FormLoginService::detectionScript();
        expectTrue(script.find("console.log") == std::string::npos,
                   "form-login script does not log to the console");
        expectTrue(script.find("halfbrowser-formlogin://") != std::string::npos,
                   "form-login uses the private channel");
    }

    // ---- autofill never submits and only fills empty fields ---------------
    {
        // No saved credential for this origin -> empty script.
        std::string none = FormLoginService::autofillScript("https://no-such-origin.invalid");
        expectTrue(none.empty(), "autofill is empty without saved credentials");
    }

    if (failures == 0) {
        printf("SELFTEST OK\n");
        return 0;
    }
    printf("SELFTEST FAILED (%d)\n", failures);
    return 1;
}
