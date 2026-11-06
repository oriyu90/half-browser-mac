#ifndef KEYCHAIN_HELPER_H
#define KEYCHAIN_HELPER_H
#include <string>

// Certificate pin storage (TOFU)
bool KeychainSaveCertPin(const std::string& host, int port, const std::string& fingerprint);
std::string KeychainLoadCertPin(const std::string& host, int port);
bool KeychainDeleteCertPin(const std::string& host, int port);

// HTTP credentials storage
bool KeychainSaveCredential(const std::string& key, const std::string& username, const std::string& password);
bool KeychainLoadCredential(const std::string& key, std::string& username, std::string& password);
bool KeychainDeleteCredential(const std::string& key);

#endif
