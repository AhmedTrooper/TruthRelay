//! Help requests feature: blood / supply / missing-person posts.

use axum::{Json, Router, extract::State, http::StatusCode, routing::post};
use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};

use crate::error::ApiError;
use crate::state::AppState;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HelpRequestInput {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub location: Option<String>,
    pub contact: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct HelpRequestView {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub body: String,
    pub location: Option<String>,
    pub contact: Option<String>,
    pub status: String,
    pub created_at: String,
    pub received_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ListResponse<T> {
    pub items: Vec<T>,
    pub next_cursor: Option<String>,
}

fn now_rfc3339() -> String {
    let now: DateTime<Utc> = Utc::now();
    now.to_rfc3339_opts(chrono::SecondsFormat::Secs, true)
}

async fn create(
    State(state): State<AppState>,
    Json(input): Json<HelpRequestInput>,
) -> Result<(StatusCode, Json<HelpRequestView>), ApiError> {
    let res = sqlx::query(
        "INSERT OR IGNORE INTO help_requests \
         (id, kind, title, body, location, contact, status, created_at) \
         VALUES (?, ?, ?, ?, ?, ?, 'Active', ?)",
    )
    .bind(&input.id)
    .bind(&input.kind)
    .bind(&input.title)
    .bind(&input.body)
    .bind(&input.location)
    .bind(&input.contact)
    .bind(&input.created_at)
    .execute(&state.db)
    .await?;

    if res.rows_affected() == 0 {
        return Err(ApiError::Conflict(format!(
            "duplicate request id {}",
            input.id
        )));
    }

    Ok((
        StatusCode::CREATED,
        Json(HelpRequestView {
            id: input.id,
            kind: input.kind,
            title: input.title,
            body: input.body,
            location: input.location,
            contact: input.contact,
            status: "Active".into(),
            created_at: input.created_at,
            received_at: now_rfc3339(),
        }),
    ))
}

async fn list(
    State(state): State<AppState>,
) -> Result<Json<ListResponse<HelpRequestView>>, ApiError> {
    let rows: Vec<(
        String,
        String,
        String,
        String,
        Option<String>,
        Option<String>,
        String,
        String,
        String,
    )> = sqlx::query_as(
        "SELECT id, kind, title, body, location, contact, status, created_at, received_at \
         FROM help_requests ORDER BY received_at DESC LIMIT 200",
    )
    .fetch_all(&state.db)
    .await?;

    let items = rows
        .into_iter()
        .map(
            |(id, kind, title, body, location, contact, status, created_at, received_at)| {
                HelpRequestView {
                    id,
                    kind,
                    title,
                    body,
                    location,
                    contact,
                    status,
                    created_at,
                    received_at,
                }
            },
        )
        .collect();

    Ok(Json(ListResponse {
        items,
        next_cursor: None,
    }))
}

// ----- Reused by sync feature --------------------------------------------

pub(crate) async fn insert_from_sync(
    state: &AppState,
    input: HelpRequestInput,
) -> Result<bool, ApiError> {
    let res = sqlx::query(
        "INSERT OR IGNORE INTO help_requests \
         (id, kind, title, body, location, contact, status, created_at) \
         VALUES (?, ?, ?, ?, ?, ?, 'Active', ?)",
    )
    .bind(&input.id)
    .bind(&input.kind)
    .bind(&input.title)
    .bind(&input.body)
    .bind(&input.location)
    .bind(&input.contact)
    .bind(&input.created_at)
    .execute(&state.db)
    .await?;
    Ok(res.rows_affected() > 0)
}

pub(crate) async fn fetch_since(
    state: &AppState,
    since: &str,
    limit: i64,
) -> Result<Vec<HelpRequestView>, ApiError> {
    let rows: Vec<(
        String,
        String,
        String,
        String,
        Option<String>,
        Option<String>,
        String,
        String,
        String,
    )> = sqlx::query_as(
        "SELECT id, kind, title, body, location, contact, status, created_at, received_at \
         FROM help_requests WHERE received_at > ? ORDER BY received_at ASC LIMIT ?",
    )
    .bind(since)
    .bind(limit)
    .fetch_all(&state.db)
    .await?;

    Ok(rows
        .into_iter()
        .map(
            |(id, kind, title, body, location, contact, status, created_at, received_at)| {
                HelpRequestView {
                    id,
                    kind,
                    title,
                    body,
                    location,
                    contact,
                    status,
                    created_at,
                    received_at,
                }
            },
        )
        .collect())
}

pub fn router() -> Router<AppState> {
    Router::new().route("/api/v1/requests", post(create).get(list))
}
