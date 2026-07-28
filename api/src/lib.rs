// `sqlx::query_as` produces raw 9+ tuples that clippy 1.95 flags as
// `type_complexity`. Extracting a `type` alias would only add ceremony —
// the schema is the source of truth and the tuple order matches it. Same
// for the `needless_borrows_for_generic_args` and `collapsible_if` lints
// surfaced by recent rust versions; the existing handlers were written
// against an older toolchain. These allows are intentional and project-
// wide so we can land new modules without re-fixing pre-existing code
// on every commit.
#![allow(clippy::type_complexity)]
#![allow(clippy::needless_borrows_for_generic_args)]
#![allow(clippy::collapsible_if)]

pub mod cli;
pub mod crypto;
pub mod db;
pub mod error;
pub mod features;
pub mod state;

pub use cli::Cmd;

use axum::Router;
use sqlx::sqlite::SqlitePoolOptions;
use tower_http::cors::{Any, CorsLayer};
use tower_http::trace::TraceLayer;

use crate::cli::ServeOpts;
use crate::state::AppState;

pub fn build_router(state: AppState) -> Router {
    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods(Any)
        .allow_headers(Any);

    Router::new()
        .merge(features::bulletins::router())
        .merge(features::requests::router())
        .merge(features::moderators::router())
        .merge(features::sync::router())
        .merge(features::mesh_forward::router())
        .merge(features::system::router())
        .layer(TraceLayer::new_for_http())
        .layer(cors)
        .with_state(state)
}

pub async fn run(opts: ServeOpts) -> anyhow::Result<()> {
    let db_url = format!("sqlite://{}?mode=rwc", opts.db.display());

    let pool = SqlitePoolOptions::new()
        .max_connections(8)
        .connect(&db_url)
        .await?;

    db::init(&pool).await?;

    let state = AppState {
        db: pool,
        admin_token: opts.admin_token,
    };

    let app = build_router(state);

    let listener = tokio::net::TcpListener::bind(&opts.bind).await?;
    tracing::info!(bind = %opts.bind, "truthrelay-api listening");
    axum::serve(listener, app).await?;
    Ok(())
}

pub async fn keygen(name: &str) -> anyhow::Result<()> {
    use base64::Engine;
    use ed25519_dalek::SigningKey;
    use rand_core::UnwrapErr;

    let mut csprng = UnwrapErr(getrandom::SysRng);
    let signing_key = SigningKey::generate(&mut csprng);
    let verifying_key = signing_key.verifying_key();

    // NOTE: `moderator_id` is intentionally NOT generated here. The server
    // assigns one when the public key is registered. Clients (web/mobile)
    // paste this JSON into the admin to register, then use the returned id.
    let payload = serde_json::json!({
        "name": name,
        "public_key_b64": base64::engine::general_purpose::STANDARD.encode(verifying_key.to_bytes()),
        "secret_key_b64": base64::engine::general_purpose::STANDARD.encode(signing_key.to_bytes()),
        "created_at": chrono::Utc::now().to_rfc3339_opts(chrono::SecondsFormat::Secs, true),
        "note": "Keep secret_key_b64 private. POST this name + public_key_b64 to /api/v1/moderators to register, then paste the full payload (including the returned id) into the web admin or mobile app.",
    });
    println!("{}", serde_json::to_string_pretty(&payload)?);
    Ok(())
}
