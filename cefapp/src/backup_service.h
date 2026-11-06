#ifndef BACKUP_SERVICE_H
#define BACKUP_SERVICE_H
#include <string>

/// Export/import of user data in the Android `halfbrowser.backup` format
/// (format="halfbrowser.backup", version=1) so a file moves between the
/// Android and macOS builds in either direction.
class BackupService {
public:
    /// Write a backup to `path`. When `passphrase` is non-empty the credential
    /// payload is encrypted with PBKDF2-HMAC-SHA256 + AES-256-GCM (Rust core).
    /// Returns "" on success or a human-readable error key on failure.
    static std::string exportBackup(const std::string& path, const std::string& passphrase);

    /// Read a backup from `path` and merge (replace=false) or replace it.
    /// Returns "" on success or an error key on failure.
    static std::string importBackup(const std::string& path, const std::string& passphrase, bool replace);

    /// Default save location (Desktop).
    static std::string defaultPath();
};

#endif
