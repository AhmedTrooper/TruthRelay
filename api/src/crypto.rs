//! Cryptographic primitives: canonical JSON bytes + Ed25519 verification.
//!
//! The canonicalization must produce *byte-identical* output across:
//!  - This Rust crate
//!  - `web/src/lib/canonical.ts`
//!  - `mobile/lib/core/canonical.dart`
//!
//! If they ever drift, signature verification will fail silently in production.

use base64::Engine;
use ed25519_dalek::{Signature, Verifier, VerifyingKey};
use serde::Serialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};

use crate::error::ApiError;

/// Build canonical bytes for a bulletin payload.
/// Keys are sorted alphabetically. Output has no trailing newline.
pub fn canonical_bulletin_bytes<P: Serialize>(payload: &P) -> Result<Vec<u8>, ApiError> {
    let value = serde_json::to_value(payload).map_err(|e| ApiError::Internal(e.to_string()))?;
    let canonical = canonicalize_value(&value);
    let s = canonical.to_string();
    Ok(s.into_bytes())
}

fn canonicalize_value(value: &Value) -> Value {
    match value {
        Value::Object(map) => {
            let mut sorted: Vec<(String, Value)> = map
                .iter()
                .map(|(k, v)| (k.clone(), canonicalize_value(v)))
                .collect();
            sorted.sort_by(|a, b| a.0.cmp(&b.0));
            let mut out = serde_json::Map::new();
            for (k, v) in sorted {
                out.insert(k, v);
            }
            Value::Object(out)
        }
        Value::Array(arr) => Value::Array(arr.iter().map(canonicalize_value).collect()),
        other => other.clone(),
    }
}

/// SHA-256 hex digest of the canonical bytes. Used to dedupe bulletins.
pub fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    let digest = hasher.finalize();
    let mut out = String::with_capacity(64);
    for b in digest {
        out.push_str(&format!("{:02x}", b));
    }
    out
}

/// Decode a base64 Ed25519 public key (32 bytes).
pub fn decode_pubkey_b64(s: &str) -> Result<[u8; 32], ApiError> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(s)
        .map_err(|_| ApiError::BadRequest("public_key_b64 is not valid base64".into()))?;
    if bytes.len() != 32 {
        return Err(ApiError::BadRequest(format!(
            "public_key_b64 must decode to 32 bytes, got {}",
            bytes.len()
        )));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(arr)
}

/// Decode a base64 Ed25519 signature (64 bytes).
pub fn decode_signature_b64(s: &str) -> Result<[u8; 64], ApiError> {
    let bytes = base64::engine::general_purpose::STANDARD
        .decode(s)
        .map_err(|_| ApiError::BadRequest("signature_b64 is not valid base64".into()))?;
    if bytes.len() != 64 {
        return Err(ApiError::BadRequest(format!(
            "signature_b64 must decode to 64 bytes, got {}",
            bytes.len()
        )));
    }
    let mut arr = [0u8; 64];
    arr.copy_from_slice(&bytes);
    Ok(arr)
}

/// Verify an Ed25519 signature over `message` against `pubkey`.
pub fn verify_ed25519(pubkey: &[u8; 32], message: &[u8], signature: &[u8; 64]) -> Result<(), ApiError> {
    let vk = VerifyingKey::from_bytes(pubkey)
        .map_err(|_| ApiError::BadRequest("invalid public key bytes".into()))?;
    let sig = Signature::from_bytes(signature);
    vk.verify(message, &sig).map_err(|_| ApiError::InvalidSignature)
}

/// Helper: build a `serde_json::Value` with the canonical keys used for signing.
/// Kept as a sanity-check / debugging aid.
#[allow(dead_code)]
pub fn canonical_payload_preview(
    kind: &str,
    title: &str,
    body: &str,
    created_at: &str,
) -> Value {
    json!({
        "body": body,
        "created_at": created_at,
        "kind": kind,
        "title": title,
    })
}