use std::path::PathBuf;

use clap::{Parser, Subcommand};

#[derive(Debug, Parser)]
#[command(name = "truthrelay", about = "TruthRelay relay server + keygen CLI")]
pub struct Cli {
    #[command(subcommand)]
    pub cmd: Cmd,
}

#[derive(Debug, Subcommand)]
pub enum Cmd {
    /// Run the HTTP relay server.
    Serve(ServeOpts),
    /// Mint a new moderator keypair and print it as JSON.
    Keygen(KeygenOpts),
}

#[derive(Debug, Parser)]
pub struct ServeOpts {
    /// Bind address, e.g. 0.0.0.0:8080
    #[arg(long, env = "TRUTHRELAY_BIND", default_value = "0.0.0.0:8080")]
    pub bind: String,

    /// Path to the SQLite database file.
    #[arg(long, env = "TRUTHRELAY_DB", default_value = "./truthrelay.db")]
    pub db: PathBuf,

    /// Shared admin token required to register moderators.
    #[arg(long, env = "TRUTHRELAY_ADMIN_TOKEN", default_value = "change-me")]
    pub admin_token: String,
}

#[derive(Debug, Parser)]
pub struct KeygenOpts {
    /// Human-readable moderator name (used as a label).
    #[arg(long)]
    pub name: String,
}
