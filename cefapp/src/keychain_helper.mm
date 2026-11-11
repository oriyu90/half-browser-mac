#import <Security/Security.h>
#import <Foundation/Foundation.h>
#include "keychain_helper.h"
#include <string>

static NSString* const kTrustService = @"half-browser-trust";
static NSString* const kCredService = @"half-browser-credentials";

bool KeychainSaveCertPin(const std::string& host, int port, const std::string& fingerprint) {
    NSString* account = [NSString stringWithFormat:@"%s:%d", host.c_str(), port];
    NSData* data = [NSData dataWithBytes:fingerprint.c_str() length:fingerprint.size()];

    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kTrustService,
        (__bridge id)kSecAttrAccount: account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSMutableDictionary* addQuery = [query mutableCopy];
    addQuery[(__bridge id)kSecValueData] = data;
    addQuery[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    return status == errSecSuccess;
}

std::string KeychainLoadCertPin(const std::string& host, int port) {
    NSString* account = [NSString stringWithFormat:@"%s:%d", host.c_str(), port];
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kTrustService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };

    CFDataRef dataRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef*)&dataRef);
    if (status != errSecSuccess || !dataRef) return "";

    NSData* data = (__bridge_transfer NSData*)dataRef;
    return std::string((const char*)[data bytes], [data length]);
}

bool KeychainDeleteCertPin(const std::string& host, int port) {
    NSString* account = [NSString stringWithFormat:@"%s:%d", host.c_str(), port];
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kTrustService,
        (__bridge id)kSecAttrAccount: account,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

bool KeychainSaveCredential(const std::string& key, const std::string& username, const std::string& password) {
    std::string value = username + ":" + password;
    NSData* data = [NSData dataWithBytes:value.c_str() length:value.size()];
    NSString* account = [NSString stringWithUTF8String:key.c_str()];

    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kCredService,
        (__bridge id)kSecAttrAccount: account,
    };
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSMutableDictionary* addQuery = [query mutableCopy];
    addQuery[(__bridge id)kSecValueData] = data;
    addQuery[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;

    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    return status == errSecSuccess;
}

bool KeychainLoadCredential(const std::string& key, std::string& username, std::string& password) {
    NSString* account = [NSString stringWithUTF8String:key.c_str()];
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kCredService,
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };

    CFDataRef dataRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef*)&dataRef);
    if (status != errSecSuccess || !dataRef) return false;

    NSData* data = (__bridge_transfer NSData*)dataRef;
    std::string value((const char*)[data bytes], [data length]);
    size_t colon = value.find(':');
    if (colon == std::string::npos) return false;
    username = value.substr(0, colon);
    password = value.substr(colon + 1);
    return true;
}

bool KeychainDeleteCredential(const std::string& key) {
    NSString* account = [NSString stringWithUTF8String:key.c_str()];
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kCredService,
        (__bridge id)kSecAttrAccount: account,
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}
// ============================================================
// Generic secret storage (WireGuard profiles)
// ============================================================
//
// WireGuard profiles contain the private key, so they live in the Keychain
// rather than in a plain JSON file. One item per profile id keeps a single
// profile's deletion independent of the others.

bool KeychainSaveSecret(const std::string& service, const std::string& account, const std::string& value) {
    NSData* data = [NSData dataWithBytes:value.c_str() length:value.size()];
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: [NSString stringWithUTF8String:service.c_str()],
        (__bridge id)kSecAttrAccount: [NSString stringWithUTF8String:account.c_str()],
    };
    SecItemDelete((__bridge CFDictionaryRef)query);

    NSMutableDictionary* addQuery = [query mutableCopy];
    addQuery[(__bridge id)kSecValueData] = data;
    addQuery[(__bridge id)kSecAttrAccessible] = (__bridge id)kSecAttrAccessibleWhenUnlocked;
    OSStatus status = SecItemAdd((__bridge CFDictionaryRef)addQuery, NULL);
    return status == errSecSuccess;
}

bool KeychainLoadSecret(const std::string& service, const std::string& account, std::string& value) {
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: [NSString stringWithUTF8String:service.c_str()],
        (__bridge id)kSecAttrAccount: [NSString stringWithUTF8String:account.c_str()],
        (__bridge id)kSecReturnData: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitOne,
    };
    CFDataRef dataRef = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef*)&dataRef);
    if (status != errSecSuccess || !dataRef) return false;
    NSData* data = (__bridge_transfer NSData*)dataRef;
    value.assign((const char*)[data bytes], [data length]);
    return true;
}

bool KeychainDeleteSecret(const std::string& service, const std::string& account) {
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: [NSString stringWithUTF8String:service.c_str()],
        (__bridge id)kSecAttrAccount: [NSString stringWithUTF8String:account.c_str()],
    };
    OSStatus status = SecItemDelete((__bridge CFDictionaryRef)query);
    return status == errSecSuccess || status == errSecItemNotFound;
}

std::vector<std::string> KeychainListAccounts(const std::string& service) {
    std::vector<std::string> out;
    NSDictionary* query = @{
        (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: [NSString stringWithUTF8String:service.c_str()],
        (__bridge id)kSecReturnAttributes: @YES,
        (__bridge id)kSecMatchLimit: (__bridge id)kSecMatchLimitAll,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return out;
    NSArray* items = (__bridge_transfer NSArray*)result;
    for (NSDictionary* item in items) {
        NSString* account = item[(__bridge id)kSecAttrAccount];
        if (account) out.push_back([account UTF8String]);
    }
    return out;
}
