//! Integration tests for the `/api/v1/mesh/forward` endpoint.
//!
//! Each test stands up an in-memory SQLite, applies the schema, builds the
//! production router, and exercises the endpoint with a real
//! `tower::ServiceExt::oneshot` round-trip so the full axum stack
//! (routing + state extraction + JSON serde + handler) is covered.
//!
//! For bulletins we sign with a freshly generated Ed25519 keypair so the
//! signature verification path runs end-to-end. For help requests we send
//! plain JSON — they are deduped by `id`.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use ed25519_dalek::{Signer, SigningKey};
use getrandom::SysRng;
use rand_core::UnwrapErr;
use serde_json::json;
use sqlx::sqlite::SqlitePoolOptions;
use tower::ServiceExt;
use truthrelay_api::build_router;
use truthrelay_api::state::AppState;

const MIGRATE_SQL: &str = include_str!("../src/migrate.sql");

async fn make_state() -> AppState {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .unwrap();

    // Apply the schema.
    for stmt in MIGRATE_SQL.split(';') {
        let trimmed = stmt.trim();
        if trimmed.is_empty() {
            continue;
        }
        sqlx::query(trimmed).execute(&pool).await.unwrap();
    }

    AppState {
        db: pool,
        admin_token: String::new(),
    }
}

async fn register_moderator(state: &AppState, name: &str, signing: &SigningKey) -> String {
    let pubkey = signing.verifying_key().to_bytes();
    let res = sqlx::query("INSERT INTO moderators (id, name, public_key) VALUES (?, ?, ?)")
        .bind(format!("mod-{name}"))
        .bind(name)
        .bind(&pubkey[..])
        .execute(&state.db)
        .await
        .unwrap();
    let _ = res;
    format!("mod-{name}")
}

fn sign_bulletin(
    moderator_id: &str,
    kind: &str,
    title: &str,
    body: &str,
    signing: &SigningKey,
) -> serde_json::Value {
    let payload = json!({
        "kind": kind,
        "title": title,
        "body": body,
        "created_at": "2026-07-29T12:00:00Z",
    });
    let canonical = serde_json::to_vec(&payload).unwrap();
    let sig = signing.sign(&canonical);
    json!({
        "moderator_id": moderator_id,
        "payload": payload,
        "signature_b64": base64::engine::general_purpose::STANDARD.encode(sig.to_bytes()),
        "id": null,
    })
}

#[tokio::test]
async fn forward_accepts_signed_bulletin_and_request() {
    let state = make_state().await;
    let mut rng = UnwrapErr(SysRng);
    let signing = SigningKey::generate(&mut rng);
    let moderator_id = register_moderator(&state, "alice", &signing).await;

    let signed = sign_bulletin(
        &moderator_id,
        "VerifiedUpdate",
        "All clear",
        "Water station open.",
        &signing,
    );
    let req = json!({
        "id": "req-001",
        "kind": "Blood",
        "title": "O+ needed",
        "body": "Family of 4",
        "location": "Block A",
        "contact": "+8801711000001",
        "created_at": "2026-07-29T12:00:00Z",
    });

    let app = build_router(state);
    let body = json!({
        "forwarder_peer_id": "phone-b",
        "bulletins": [signed],
        "requests": [req],
    });
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/mesh/forward")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(parsed["accepted"], 2);
    assert_eq!(parsed["duplicates"], 0);
    assert_eq!(parsed["rejected"], 0);
    assert_eq!(parsed["forwarder_peer_id"], "phone-b");
}

#[tokio::test]
async fn forward_counts_duplicates_as_idempotent() {
    let state = make_state().await;
    let mut rng = UnwrapErr(SysRng);
    let signing = SigningKey::generate(&mut rng);
    let moderator_id = register_moderator(&state, "bob", &signing).await;
    let signed = sign_bulletin(
        &moderator_id,
        "Debunk",
        "Old rumor",
        "Clinic never closed.",
        &signing,
    );

    let app = build_router(state);
    let body = json!({
        "forwarder_peer_id": "phone-c",
        "bulletins": [signed.clone()],
        "requests": [],
    });
    // First send.
    let resp = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/mesh/forward")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);

    // Second send of the SAME bulletin should be a duplicate, not an error.
    let resp2 = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/mesh/forward")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp2.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(resp2.into_body(), usize::MAX)
        .await
        .unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(parsed["accepted"], 0);
    assert_eq!(parsed["duplicates"], 1);
}

#[tokio::test]
async fn forward_rejects_bulletin_with_bad_signature() {
    let state = make_state().await;
    let mut rng = UnwrapErr(SysRng);
    let signing = SigningKey::generate(&mut rng);
    let moderator_id = register_moderator(&state, "carol", &signing).await;

    // Sign with one key but register a different public key for the moderator
    // — the verification step should fail.
    let signing_other = SigningKey::generate(&mut rng);
    let signed = sign_bulletin(
        &moderator_id,
        "VerifiedUpdate",
        "Fake",
        "Body",
        &signing_other,
    );

    let app = build_router(state);
    let body = json!({
        "forwarder_peer_id": "phone-d",
        "bulletins": [signed],
        "requests": [],
    });
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/mesh/forward")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(parsed["rejected"], 1);
    assert_eq!(parsed["accepted"], 0);
}

#[tokio::test]
async fn forward_rejects_bulletin_from_unknown_moderator() {
    let state = make_state().await;
    let mut rng = UnwrapErr(SysRng);
    let signing = SigningKey::generate(&mut rng);
    let signed = sign_bulletin(
        "mod-never-registered",
        "VerifiedUpdate",
        "Hi",
        "Body",
        &signing,
    );

    let app = build_router(state);
    let body = json!({
        "forwarder_peer_id": "phone-e",
        "bulletins": [signed],
        "requests": [],
    });
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/mesh/forward")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(parsed["rejected"], 1);
}

#[tokio::test]
async fn forward_empty_payload_returns_zero_counts() {
    let state = make_state().await;
    let app = build_router(state);
    let body = json!({
        "forwarder_peer_id": "phone-f",
        "bulletins": [],
        "requests": [],
    });
    let resp = app
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/v1/mesh/forward")
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(resp.status(), StatusCode::OK);
    let body_bytes = axum::body::to_bytes(resp.into_body(), usize::MAX)
        .await
        .unwrap();
    let parsed: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert_eq!(parsed["accepted"], 0);
    assert_eq!(parsed["duplicates"], 0);
    assert_eq!(parsed["rejected"], 0);
    assert_eq!(parsed["forwarder_peer_id"], "phone-f");
}
