//! System feature: healthz and stats endpoints.

use axum::{extract::State, routing::get, Json, Router};
use serde_json::{json, Value};

use crate::error::ApiError;
use crate::state::AppState;

async fn healthz() -> Json<Value> {
    Json(json!({ "status": "ok" }))
}

async fn stats(
    State(state): State<AppState>,
) -> Result<Json<Value>, ApiError> {
    let bulletins: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM bulletins")
        .fetch_one(&state.db)
        .await?;
    let requests: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM help_requests")
        .fetch_one(&state.db)
        .await?;
    let moderators: (i64,) = sqlx::query_as("SELECT COUNT(*) FROM moderators")
        .fetch_one(&state.db)
        .await?;

    Ok(Json(json!({
        "bulletins": bulletins.0,
        "requests": requests.0,
        "moderators": moderators.0,
    })))
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/healthz", get(healthz))
        .route("/api/v1/stats", get(stats))
}