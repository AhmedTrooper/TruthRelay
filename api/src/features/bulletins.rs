//! Bulletins feature: signed, moderator-attested updates.
//!
//! Owns: routes, DTOs, persistence, signature verification.

use axum::{
    Json, Router,
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
};
use base64::Engine;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::crypto::{canonical_bulletin_bytes, decode_signature_b64, sha256_hex, verify_ed25519};
use crate::error::ApiError;
use crate::state::AppState;

// ----- DTOs --------------------------------------------------------------

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulletinPayload {
    pub kind: String,
    pub title: String,
    pub body: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SignedBulletin {
    pub moderator_id: String,
    pub payload: BulletinPayload,
    pub signature_b64: String,
    pub id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BulletinView {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub sha256: String,
    pub status: String,
    pub moderator_id: String,
    pub moderator_name: Option<String>,
    pub signature_b64: String,
    pub created_at: String,
    pub received_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListResponse<T> {
    pub items: Vec<T>,
    pub next_cursor: Option<String>,
}

// ----- Persistence -------------------------------------------------------

async fn fetch_pubkey(state: &AppState, moderator_id: &str) -> Result<[u8; 32], ApiError> {
    let row: Option<(Vec<u8>,)> = sqlx::query_as("SELECT public_key FROM moderators WHERE id = ?")
        .bind(moderator_id)
        .fetch_optional(&state.db)
        .await?;
    let bytes = row
        .ok_or_else(|| ApiError::UnknownModerator(moderator_id.to_string()))?
        .0;
    if bytes.len() != 32 {
        return Err(ApiError::Internal(
            "moderator pubkey has wrong length".into(),
        ));
    }
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&bytes);
    Ok(arr)
}

async fn moderator_name(state: &AppState, moderator_id: &str) -> Option<String> {
    let row: Option<(String,)> = sqlx::query_as("SELECT name FROM moderators WHERE id = ?")
        .bind(moderator_id)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten();
    row.map(|(n,)| n)
}

fn now_rfc3339() -> String {
    let now: DateTime<Utc> = Utc::now();
    now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

// ----- Handlers -----------------------------------------------------------

async fn create(
    State(state): State<AppState>,
    Json(input): Json<SignedBulletin>,
) -> Result<(StatusCode, Json<BulletinView>), ApiError> {
    // 1. Decode signature.
    let sig_bytes = decode_signature_b64(&input.signature_b64)?;
    let canonical = canonical_bulletin_bytes(&input.payload)?;

    // 2. Compute dedup hash.
    let sha = sha256_hex(&canonical);

    // 3. Look up moderator's public key.
    let pubkey = fetch_pubkey(&state, &input.moderator_id).await?;

    // 4. Verify signature.
    verify_ed25519(&pubkey, &canonical, &sig_bytes)?;

    // 5. Resolve or generate the client-side id.
    let id = input.id.unwrap_or_else(|| Uuid::new_v4().to_string());

    // 6. Insert. If duplicate by id or sha256, return 409.
    let result = sqlx::query(
        "INSERT INTO bulletins \
         (id, kind, title, body, sha256, status, moderator_id, signature, payload_json, created_at) \
         VALUES (?, ?, ?, ?, ?, 'Active', ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&input.payload.kind)
    .bind(&input.payload.title)
    .bind(&input.payload.body)
    .bind(&sha)
    .bind(&input.moderator_id)
    .bind(&sig_bytes.to_vec())
    .bind(String::from_utf8_lossy(&canonical).to_string())
    .bind(&input.payload.created_at)
    .execute(&state.db)
    .await;

    if let Err(e) = result {
        if let sqlx::Error::Database(db_err) = &e {
            if db_err.code().as_deref() == Some("2067")
                || db_err.message().contains("UNIQUE constraint failed")
            {
                return Err(ApiError::Conflict(format!(
                    "duplicate bulletin (sha256={})",
                    &sha[..16]
                )));
            }
        }
        return Err(e.into());
    }

    let view = BulletinView {
        id: id.clone(),
        kind: input.payload.kind.clone(),
        title: input.payload.title.clone(),
        body: input.payload.body.clone(),
        sha256: sha.clone(),
        status: "Active".into(),
        moderator_id: input.moderator_id.clone(),
        moderator_name: moderator_name(&state, &input.moderator_id).await,
        signature_b64: input.signature_b64.clone(),
        created_at: input.payload.created_at.clone(),
        received_at: now_rfc3339(),
    };

    Ok((StatusCode::CREATED, Json(view)))
}

async fn list(State(state): State<AppState>) -> Result<Json<ListResponse<BulletinView>>, ApiError> {
    let rows: Vec<(
        String,
        String,
        String,
        String,
        String,
        String,
        String,
        Vec<u8>,
        String,
        String,
    )> = sqlx::query_as(
        "SELECT id, kind, title, body, sha256, status, moderator_id, signature, created_at, received_at \
         FROM bulletins ORDER BY received_at DESC LIMIT 200",
    )
    .fetch_all(&state.db)
    .await?;

    let mut items = Vec::with_capacity(rows.len());
    for (id, kind, title, body, sha256, status, moderator_id, signature, created_at, received_at) in
        rows
    {
        items.push(BulletinView {
            id,
            kind,
            title,
            body,
            sha256,
            status,
            moderator_id: moderator_id.clone(),
            moderator_name: moderator_name(&state, &moderator_id).await,
            signature_b64: base64::engine::general_purpose::STANDARD.encode(&signature),
            created_at,
            received_at,
        });
    }
    Ok(Json(ListResponse {
        items,
        next_cursor: None,
    }))
}

async fn get_one(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<BulletinView>, ApiError> {
    let row: Option<(
        String,
        String,
        String,
        String,
        String,
        String,
        Vec<u8>,
        String,
        String,
    )> = sqlx::query_as(
        "SELECT id, kind, title, body, sha256, status, signature, created_at, received_at \
         FROM bulletins WHERE id = ?",
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?;

    let (id, kind, title, body, sha256, status, signature, created_at, received_at) =
        row.ok_or_else(|| ApiError::NotFound(format!("bulletin {id}")))?;

    // We need moderator_id; redo the query to grab it.
    let mid_row: Option<(String,)> =
        sqlx::query_as("SELECT moderator_id FROM bulletins WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;
    let moderator_id = mid_row
        .ok_or_else(|| ApiError::NotFound(format!("bulletin {id}")))?
        .0;

    Ok(Json(BulletinView {
        id,
        kind,
        title,
        body,
        sha256,
        status,
        moderator_id: moderator_id.clone(),
        moderator_name: moderator_name(&state, &moderator_id).await,
        signature_b64: base64::engine::general_purpose::STANDARD.encode(&signature),
        created_at,
        received_at,
    }))
}

// ----- Reused by sync feature --------------------------------------------

pub(crate) async fn insert_from_sync(
    state: &AppState,
    input: SignedBulletin,
) -> Result<(bool, String), ApiError> {
    let sig_bytes = decode_signature_b64(&input.signature_b64)?;
    let canonical = canonical_bulletin_bytes(&input.payload)?;
    let sha = sha256_hex(&canonical);
    let pubkey = fetch_pubkey(state, &input.moderator_id).await?;
    verify_ed25519(&pubkey, &canonical, &sig_bytes)?;
    let id = input.id.unwrap_or_else(|| Uuid::new_v4().to_string());

    let res = sqlx::query(
        "INSERT OR IGNORE INTO bulletins \
         (id, kind, title, body, sha256, status, moderator_id, signature, payload_json, created_at) \
         VALUES (?, ?, ?, ?, ?, 'Active', ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&input.payload.kind)
    .bind(&input.payload.title)
    .bind(&input.payload.body)
    .bind(&sha)
    .bind(&input.moderator_id)
    .bind(&sig_bytes.to_vec())
    .bind(String::from_utf8_lossy(&canonical).to_string())
    .bind(&input.payload.created_at)
    .execute(&state.db)
    .await?;

    Ok((res.rows_affected() > 0, sha))
}

pub(crate) async fn fetch_since(
    state: &AppState,
    since: &str,
    limit: i64,
) -> Result<Vec<BulletinView>, ApiError> {
    let rows: Vec<(
        String,
        String,
        String,
        String,
        String,
        String,
        String,
        Vec<u8>,
        String,
        String,
    )> = sqlx::query_as(
        "SELECT id, kind, title, body, sha256, status, moderator_id, signature, created_at, received_at \
         FROM bulletins WHERE received_at > ? ORDER BY received_at ASC LIMIT ?",
    )
    .bind(since)
    .bind(limit)
    .fetch_all(&state.db)
    .await?;

    let mut items = Vec::with_capacity(rows.len());
    for (id, kind, title, body, sha256, status, moderator_id, signature, created_at, received_at) in
        rows
    {
        items.push(BulletinView {
            id,
            kind,
            title,
            body,
            sha256,
            status,
            moderator_id: moderator_id.clone(),
            moderator_name: moderator_name(state, &moderator_id).await,
            signature_b64: base64::engine::general_purpose::STANDARD.encode(&signature),
            created_at,
            received_at,
        });
    }
    Ok(items)
}

// ----- Router -------------------------------------------------------------

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/bulletins", post(create).get(list))
        .route("/api/v1/bulletins/{id}", get(get_one))
}

#[allow(dead_code)]
pub(crate) fn debug_summary(v: &BulletinView) -> Value {
    json!({
        "id": v.id,
        "kind": v.kind,
        "title": v.title,
    })
}
