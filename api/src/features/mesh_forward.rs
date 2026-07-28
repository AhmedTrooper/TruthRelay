//! Mesh-forwarding feature: relay another peer's queued data.
//!
//! When a phone has connectivity but its neighbour does not, the connected
//! phone may act as a "carrier" — it receives the offline phone's queued
//! outbox (bulletins + help requests) over a local mesh transport and
//! forwards them to this server. Trust is enforced server-side: each
//! bulletin still must carry a valid Ed25519 signature from a registered
//! moderator, and each help request is deduplicated by `id`.
//!
//! This is the same idempotent insertion path that
//! [`crate::features::sync`] uses, just exposed under a route name that
//! makes the mesh-forwarding intent explicit in mobile logs.

use axum::{Json, Router, extract::State, http::StatusCode, routing::post};
use serde::{Deserialize, Serialize};

use crate::error::ApiError;
use crate::features::{bulletins, requests};
use crate::state::AppState;

#[derive(Debug, Deserialize)]
pub struct MeshForward {
    /// The forwarding phone's per-install id. Recorded for audit; not used
    /// for trust decisions — trust is enforced by signature verification.
    #[serde(default)]
    pub forwarder_peer_id: Option<String>,
    #[serde(default)]
    pub bulletins: Vec<bulletins::SignedBulletin>,
    #[serde(default)]
    pub requests: Vec<requests::HelpRequestInput>,
}

#[derive(Debug, Serialize)]
pub struct MeshForwardResult {
    pub accepted: u32,
    pub duplicates: u32,
    pub rejected: u32,
    pub forwarder_peer_id: Option<String>,
    pub server_time: String,
}

async fn forward(
    State(state): State<AppState>,
    Json(payload): Json<MeshForward>,
) -> Result<(StatusCode, Json<MeshForwardResult>), ApiError> {
    let mut accepted: u32 = 0;
    let mut duplicates: u32 = 0;
    let mut rejected: u32 = 0;

    for b in payload.bulletins {
        match bulletins::insert_from_sync(&state, b).await {
            Ok((true, _)) => accepted += 1,
            Ok((false, _)) => duplicates += 1,
            Err(ApiError::Conflict(_)) => duplicates += 1,
            Err(ApiError::UnknownModerator(_)) => rejected += 1,
            Err(ApiError::InvalidSignature) => rejected += 1,
            Err(ApiError::BadRequest(_)) => rejected += 1,
            Err(e) => return Err(e),
        }
    }

    for r in payload.requests {
        match requests::insert_from_sync(&state, r).await {
            Ok(true) => accepted += 1,
            Ok(false) => duplicates += 1,
            Err(ApiError::Conflict(_)) => duplicates += 1,
            Err(ApiError::BadRequest(_)) => rejected += 1,
            Err(e) => return Err(e),
        }
    }

    Ok((
        StatusCode::OK,
        Json(MeshForwardResult {
            accepted,
            duplicates,
            rejected,
            forwarder_peer_id: payload.forwarder_peer_id,
            server_time: chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        }),
    ))
}

pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/mesh/forward", post(forward))
}
