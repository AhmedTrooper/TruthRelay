//! Moderators feature: register and fetch Ed25519 public keys.

use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use base64::Engine;
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModeratorInput {
    pub name: String,
    pub public_key_b64: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ModeratorView {
    pub id: String,
    pub name: String,
    pub public_key_b64: String,
    pub created_at: String,
}

fn now_rfc3339() -> String {
    let now: DateTime<Utc> = Utc::now();
    now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

fn check_admin(headers: &HeaderMap, expected: &str) -> Result<(), ApiError> {
    let provided = headers
        .get("x-admin-token")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    if provided != expected {
        Err(ApiError::Unauthorized)
    } else {
        Ok(())
    }
}

async fn create(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(input): Json<ModeratorInput>,
) -> Result<(StatusCode, Json<ModeratorView>), ApiError> {
    check_admin(&headers, &state.admin_token)?;

    let bytes = base64::engine::general_purpose::STANDARD
        .decode(&input.public_key_b64)
        .map_err(|_| ApiError::BadRequest("public_key_b64 not valid base64".into()))?;
    if bytes.len() != 32 {
        return Err(ApiError::BadRequest(format!(
            "public_key_b64 must decode to 32 bytes, got {}",
            bytes.len()
        )));
    }

    let id = Uuid::new_v4().to_string();
    let created_at = now_rfc3339();

    sqlx::query("INSERT INTO moderators (id, name, public_key, created_at) VALUES (?, ?, ?, ?)")
        .bind(&id)
        .bind(&input.name)
        .bind(&bytes)
        .bind(&created_at)
        .execute(&state.db)
        .await?;

    Ok((
        StatusCode::CREATED,
        Json(ModeratorView {
            id,
            name: input.name,
            public_key_b64: input.public_key_b64,
            created_at,
        }),
    ))
}

async fn get_one(
    State(state): State<AppState>,
    Path(id): Path<String>,
) -> Result<Json<ModeratorView>, ApiError> {
    let row: Option<(String, Vec<u8>, String)> = sqlx::query_as(
        "SELECT name, public_key, created_at FROM moderators WHERE id = ?",
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?;

    let (name, public_key, created_at) = row.ok_or_else(|| {
        ApiError::NotFound(format!("moderator {id}"))
    })?;

    Ok(Json(ModeratorView {
        id,
        name,
        public_key_b64: base64::engine::general_purpose::STANDARD.encode(&public_key),
        created_at,
    }))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/api/v1/moderators", post(create))
        .route("/api/v1/moderators/{id}", get(get_one))
}