#ifndef KEYCHAIN_HELPER_H
#define KEYCHAIN_HELPER_H
#include <string>
#include <vector>

// Certificate pin storage (TOFU)
bool KeychainSaveCertPin(const std::string& host, int port, const std::string& fingerprint);
std::string KeychainLoadCertPin(const std::string& host, int port);
bool KeychainDeleteCertPin(const std::string& host, int port);

// HTTP credentials storage
bool KeychainSaveCredential(const std::string& key, const std::string& username, const std::string& password);
bool KeychainLoadCredential(const std::string& key, std::string& username, std::string& password);
bool KeychainDeleteCredential(const std::string& key);

// Generic secret storage, used for WireGuard profiles (which contain private
// keys). Kept separate from the credential service so a profile and an HTTP
// credential can never collide.
bool KeychainSaveSecret(const std::string& service, const std::string& account, const std::string& value);
bool KeychainLoadSecret(const std::string& service, const std::string& account, std::string& value);
bool KeychainDeleteSecret(const std::string& service, const std::string& account);
/// Lists the accounts stored under `service` (empty when none or on error).
std::vector<std::string> KeychainListAccounts(const std::string& service);

#endif
