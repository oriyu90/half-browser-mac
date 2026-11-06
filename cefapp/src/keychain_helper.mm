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