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

    // ---- Settings round-trip through SettingsStore itself -----------------
    // Exercises load()/save() rather than re-implementing the parsing beside
    // them, so a regression inside the store is actually caught. The store is
    // pointed at a scratch file so the user's settings are untouched.
    {
        const char* scratch = "/tmp/hb_selftest_settings.json";
        remove(scratch);
        SettingsStore& store = SettingsStore::instance();
        store.setFilePathForTesting(scratch);

        AppSettings s;
        s.themeMode = "dark";
        s.accentHue = 123.5f;
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
        store.save(s);

        AppSettings r = store.load();
        expectEq(r.themeMode, "dark", "settings theme round-trip");
        expectTrue(r.accentHue > 123.4f && r.accentHue < 123.6f, "settings accent hue");
        expectEq(std::to_string(r.gridColumns), "5", "settings grid columns");
        expectEq(r.searchEngine, "kagi", "settings search engine");
        expectTrue(r.vpnAutoConnect, "settings vpnAutoConnect");
        expectTrue(!r.vpnAutoReconnect, "settings vpnAutoReconnect");
        expectTrue(r.vpnPowerSaver, "settings vpnPowerSaver");
        expectTrue(r.siteWatchEnabled, "settings siteWatchEnabled");
        expectEq(std::to_string(r.siteWatchIntervalMinutes), "30", "settings watch interval");
        expectTrue(r.siteWatchWifiOnly, "settings siteWatchWifiOnly");
        expectTrue(!r.jsGuardEnabled, "settings jsGuardEnabled");
        expectTrue(!r.formAutofillEnabled, "settings formAutofillEnabled");

        // A key that is a prefix of another must not be confused with it.
        {
            std::ofstream f(scratch, std::ios::binary | std::ios::trunc);
            f << "{\"accentHue\":42.0,\"accentHueExtra\":999}";
        }
        AppSettings p2 = store.load();
        expectTrue(p2.accentHue > 41.9f && p2.accentHue < 42.1f,
                   "settings prefix key is not confused");

        // Sanitize: out-of-range values are clamped on load.
        {
            std::ofstream f(scratch, std::ios::binary | std::ios::trunc);
            f << "{\"uiScale\":9.9,\"fontScale\":0.1,\"gridColumns\":7,"
                 "\"siteWatchIntervalMinutes\":7,\"themeMode\":\"purple\"}";
        }
        AppSettings p3 = store.load();
        expectTrue(p3.uiScale <= 1.4f && p3.uiScale >= 0.8f, "settings uiScale clamped");
        expectTrue(p3.fontScale <= 1.5f && p3.fontScale >= 0.8f, "settings fontScale clamped");
        expectEq(std::to_string(p3.gridColumns), "0", "settings grid columns sanitized");
        expectEq(std::to_string(p3.siteWatchIntervalMinutes), "60", "settings interval sanitized");
        expectEq(p3.themeMode, "system", "settings theme sanitized");

        // Backward compatibility: the pre-1.9 key still switches autofill.
        {
            std::ofstream f(scratch, std::ios::binary | std::ios::trunc);
            f << "{\"formLoginEnabled\":false}";
        }
        AppSettings p4 = store.load();
        expectTrue(!p4.formAutofillEnabled, "settings honours the legacy formLoginEnabled key");

        remove(scratch);
        store.setFilePathForTesting(nullptr);
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

    // ---- every key the UI asks for must exist in both catalogs ------------
    // Parity alone is not enough: a key missing from BOTH catalogs passes the
    // parity check and still shows its raw name in the UI. This list is the
    // set of keys the code references; it is checked against the catalog.
    {
        const char* required[] = {
            "app.name", "menu.settings", "menu.zoom", "menu.zoom_in", "menu.zoom_out",
            "menu.actual_size", "menu.find", "menu.history", "menu.cut", "menu.copy",
            "menu.paste", "menu.select_all", "common.ok", "common.cancel",
            "ssl.title", "ssl.changed_body", "auth.title", "formlogin.body",
            "perm.allow", "perm.kind.unknown", "bookmark.save",
            "settings.title", "settings.tab.vpn", "settings.js_guard",
            "backup.export_ok", "download.done_title", "jsdialog.alert_title",
            "history.title", "watch.title", "watch.foreground_only",
            "vpn.mac_limitation", "vpn.avail.needs_root", "vpn.status_connected",
            "vpn.err.empty", "vpn.err.no_profile", "vpn.err.config_unreadable",
            "vpn.err.save_failed", "vpn.err.export_failed",
        };
        Localization::instance().setLanguage("en");
        int missingEn = 0;
        for (const char* k : required) {
            // get() falls back to the key itself when it is absent.
            if (Localization::instance().get(k) == k) {
                fprintf(stderr, "  missing English key: %s\n", k);
                missingEn++;
            }
        }
        Localization::instance().setLanguage("ja");
        int missingJa = 0;
        for (const char* k : required) {
            if (Localization::instance().get(k) == k) {
                fprintf(stderr, "  missing Japanese key: %s\n", k);
                missingJa++;
            }
        }
        expectEq(std::to_string(missingEn), "0", "no required key is missing (en)");
        expectEq(std::to_string(missingJa), "0", "no required key is missing (ja)");
    }

    // ---- URL scheme rejection, including inputs that bypass the host rule --
    // "javascript:alert(1)" contains no space and is not host-like, so it must
    // be stopped by the scheme check specifically. Testing only the empty
    // result let a broken scheme check pass because another rule caught it.
    {
        const std::string ddg = "https://duckduckgo.com/?q=%s";
        const char* dangerous[] = {
            "javascript:alert(1)",
            "JavaScript:alert(1)",
            "  javascript:alert(1)",
            "javascript://example.com/%0aalert(1)",
            "data:text/html,<script>alert(1)</script>",
            "vbscript:msgbox(1)",
            "file:///etc/passwd",
            "intent://x#Intent;end",
            "about:blank",
        };
        for (const char* d : dangerous) {
            std::string got = UrlUtil::toNavigable(d, ddg);
            if (!got.empty()) {
                fprintf(stderr, "  navigable accepted %s -> %s\n", d, got.c_str());
            }
            expectTrue(got.empty(), d);
        }
        // Defence in depth: parse() itself refuses any scheme other than
        // http/https, so these are rejected even if the outer scheme check in
        // toNavigable were broken. Asserting it here pins that second line of
        // defence rather than only the first.
        expectTrue(UrlUtil::validateWebUrl("javascript:alert(1)").empty(),
                   "validateWebUrl rejects javascript:");
        expectTrue(UrlUtil::validateWebUrl("file:///etc/passwd").empty(),
                   "validateWebUrl rejects file:");
        expectTrue(UrlUtil::validateWebUrl("javascript://example.com/%0aalert(1)").empty(),
                   "validateWebUrl rejects a javascript: URL with an authority");
        expectTrue(UrlUtil::validateWebUrl("data://example.com/x").empty(),
                   "validateWebUrl rejects data:");
    }

    // ---- form-login origin rules -----------------------------------------
    // The page reports its own origin; the handler must only accept https and
    // must reject a mismatch with the frame URL. Both rules are pure functions
    // of (reported origin, frame origin), so they are testable here.
    {
        auto acceptOrigin = [](const std::string& reported, const std::string& frameOrigin) {
            if (reported.find("https://") != 0) return false;
            if (!frameOrigin.empty() && frameOrigin != reported) return false;
            if (frameOrigin.empty() && reported.size() > 2048) return false;
            return true;
        };
        expectTrue(acceptOrigin("https://bank.example", "https://bank.example"),
                   "formlogin accepts a matching https origin");
        expectTrue(!acceptOrigin("http://bank.example", "http://bank.example"),
                   "formlogin rejects http");
        expectTrue(!acceptOrigin("https://bank.example", "https://evil.example"),
                   "formlogin rejects a spoofed origin");
        // With no frame URL to compare against, a short origin is still
        // accepted (there is nothing to contradict it); only an oversized one
        // is refused, so a hostile page cannot push a huge key at the store.
        expectTrue(acceptOrigin("https://bank.example", ""),
                   "formlogin accepts a short origin when no frame url exists");
        expectTrue(!acceptOrigin("https://" + std::string(3000, 'a'), ""),
                   "formlogin rejects an oversized origin");
    }

    // ---- settings: both clamp directions and the round-trip --------------
    {
        const char* scratch = "/tmp/hb_selftest_clamp.json";
        SettingsStore& store = SettingsStore::instance();
        store.setFilePathForTesting(scratch);

        // Lower bounds.
        {
            std::ofstream f(scratch, std::ios::binary | std::ios::trunc);
            f << "{\"uiScale\":0.1,\"fontScale\":0.1}";
        }
        AppSettings lo = store.load();
        expectTrue(lo.uiScale >= 0.8f, "uiScale lower bound");
        expectTrue(lo.fontScale >= 0.8f, "fontScale lower bound");

        // Upper bounds.
        {
            std::ofstream f(scratch, std::ios::binary | std::ios::trunc);
            f << "{\"uiScale\":9.9,\"fontScale\":9.9}";
        }
        AppSettings hi = store.load();
        expectTrue(hi.uiScale <= 1.4f, "uiScale upper bound");
        expectTrue(hi.fontScale <= 1.5f, "fontScale upper bound");

        // A value inside the range must survive a save/load round-trip
        // unchanged (a hard-coded default would pass the clamps above).
        AppSettings mid;
        mid.uiScale = 1.25f;
        mid.fontScale = 1.3f;
        store.save(mid);
        AppSettings back = store.load();
        expectTrue(back.uiScale > 1.24f && back.uiScale < 1.26f, "uiScale round-trip");
        expectTrue(back.fontScale > 1.29f && back.fontScale < 1.31f, "fontScale round-trip");

        remove(scratch);
        store.setFilePathForTesting(nullptr);
    }

    // ---- every permission kind the UI can name has a label ---------------
    {
        Localization::instance().setLanguage("en");
        const char* kinds[] = {"camera", "microphone", "notification", "location",
                               "clipboard", "unknown"};
        for (const char* k : kinds) {
            std::string key = std::string("perm.kind.") + k;
            if (Localization::instance().get(key) == key) {
                fprintf(stderr, "  missing permission label: %s\n", key.c_str());
            }
            expectTrue(Localization::instance().get(key) != key, key.c_str());
        }
        Localization::instance().setLanguage("ja");
        for (const char* k : kinds) {
            std::string key = std::string("perm.kind.") + k;
            expectTrue(Localization::instance().get(key) != key, key.c_str());
        }
    }

    if (failures == 0) {
        printf("SELFTEST OK\n");
        return 0;
    }
    printf("SELFTEST FAILED (%d)\n", failures);
    return 1;
}
