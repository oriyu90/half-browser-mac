//! Ported from Android `core/BackupCrypto.kt`.

use aes_gcm::aead::{Aead, KeyInit};
use aes_gcm::{Aes256Gcm, Nonce};
use base64::{engine::general_purpose::STANDARD, Engine};
use getrandom::getrandom;
use pbkdf2::pbkdf2_hmac;
use sha2::Sha256;

pub const SCHEME: &str = "pbkdf2-hmac-sha256/aes-256-gcm";
pub const DEFAULT_ITERATIONS: u32 = 120_000;
pub const MIN_PASSPHRASE_LENGTH: usize = 8;
pub const MAX_PASSPHRASE_LENGTH: usize = 256;
const SALT_BYTES: usize = 16;
const IV_BYTES: usize = 12;
const KEY_BITS: usize = 256;

#[derive(Debug, Clone)]
pub struct Encrypted {
    pub salt: String,
    pub iv: String,
    pub ciphertext: String,
    pub iterations: u32,
}

pub struct BackupCrypto;

impl BackupCrypto {
    pub fn is_acceptable_passphrase(pass: &[u8]) -> bool {
        pass.len() >= MIN_PASSPHRASE_LENGTH && pass.len() <= MAX_PASSPHRASE_LENGTH
    }

    pub fn encrypt(plaintext: &str, passphrase: &[u8]) -> Option<Encrypted> {
        if !Self::is_acceptable_passphrase(passphrase) {
            return None;
        }
        let mut salt = [0u8; SALT_BYTES];
        let mut iv = [0u8; IV_BYTES];
        getrandom(&mut salt).ok()?;
        getrandom(&mut iv).ok()?;

        let mut key = [0u8; KEY_BITS / 8];
        pbkdf2_hmac::<Sha256>(passphrase, &salt, DEFAULT_ITERATIONS, &mut key);

        let cipher = Aes256Gcm::new_from_slice(&key).ok()?;
        let nonce = Nonce::from_slice(&iv);
        let ct = cipher.encrypt(nonce, plaintext.as_bytes()).ok()?;

        Some(Encrypted {
            salt: STANDARD.encode(salt),
            iv: STANDARD.encode(iv),
            ciphertext: STANDARD.encode(ct),
            iterations: DEFAULT_ITERATIONS,
        })
    }

    pub fn decrypt(payload: &Encrypted, passphrase: &[u8]) -> Option<String> {
        if !Self::is_acceptable_passphrase(passphrase) {
            return None;
        }
        if payload.iterations == 0 || payload.iterations > 1_000_000 {
            return None;
        }
        let salt = STANDARD.decode(&payload.salt).ok()?;
        let iv = STANDARD.decode(&payload.iv).ok()?;
        let data = STANDARD.decode(&payload.ciphertext).ok()?;
        if salt.len() < SALT_BYTES || iv.len() != IV_BYTES {
            return None;
        }
        let mut key = [0u8; KEY_BITS / 8];
        pbkdf2_hmac::<Sha256>(passphrase, &salt, payload.iterations, &mut key);

        let cipher = Aes256Gcm::new_from_slice(&key).ok()?;
        let nonce = Nonce::from_slice(&iv);
        let pt = cipher.decrypt(nonce, data.as_slice()).ok()?;
        String::from_utf8(pt).ok()
    }
}