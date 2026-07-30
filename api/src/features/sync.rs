//! Sync feature: bulk push/pull for offline-first clients.
//!
//! - POST /api/v1/sync accepts a batch of signed bulletins + help requests
//! - GET /api/v1/sync?since=<rfc3339>&limit=<n> returns everything since

use axum::{
    Json, Router,
    extract::{Query, State},
    routing::post,
};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::ApiError;
use crate::features::{bulletins, requests};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct SyncQuery {
    #[serde(default)]
    pub since: Option<String>,
    #[serde(default = "default_limit")]
    pub limit: i64,
}

fn default_limit() -> i64 {
    200
}

#[derive(Debug, Deserialize)]
pub struct SyncPush {
    #[serde(default)]
    pub bulletins: Vec<bulletins::SignedBulletin>,
    #[serde(default)]
    pub requests: Vec<requests::HelpRequestInput>,
}

#[derive(Debug, Serialize)]
pub struct SyncPushResult {
    pub accepted: u32,
    pub duplicates: u32,
}

#[derive(Debug, Serialize)]
pub struct SyncPull {
    pub bulletins: Vec<bulletins::BulletinView>,
    pub requests: Vec<requests::HelpRequestView>,
    pub server_time: String,
}

fn now_rfc3339() -> String {
    let now: DateTime<Utc> = Utc::now();
    now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

async fn push(
    State(state): State<AppState>,
    Json(payload): Json<SyncPush>,
) -> Result<Json<SyncPushResult>, ApiError> {
    let mut accepted: u32 = 0;
    let mut duplicates: u32 = 0;

    for b in payload.bulletins {
        match bulletins::insert_from_sync(&state, b).await {
            Ok((true, _)) => accepted += 1,
            Ok((false, _)) => duplicates += 1,
            Err(ApiError::Conflict(_)) => duplicates += 1,
            Err(e) => return Err(e),
        }
    }

    for r in payload.requests {
        match requests::insert_from_sync(&state, r).await {
            Ok(true) => accepted += 1,
            Ok(false) => duplicates += 1,
            Err(ApiError::Conflict(_)) => duplicates += 1,
            Err(e) => return Err(e),
        }
    }

    Ok(Json(SyncPushResult {
        accepted,
        duplicates,
    }))
}

async fn pull(
    State(state): State<AppState>,
    Query(q): Query<SyncQuery>,
) -> Result<Json<SyncPull>, ApiError> {
    let since = q
        .since
        .unwrap_or_else(|| "1970-01-01T00:00:00Z".to_string());
    let limit = q.limit.clamp(1, 1000);

    let bulletins_vec = bulletins::fetch_since(&state, &since, limit).await?;
    let requests_vec = requests::fetch_since(&state, &since, limit).await?;

    Ok(Json(SyncPull {
        bulletins: bulletins_vec,
        requests: requests_vec,
        server_time: now_rfc3339(),
    }))
}

pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/sync", post(push).get(pull))
}
