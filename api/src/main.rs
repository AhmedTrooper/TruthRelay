use clap::Parser;
use tracing_subscriber::EnvFilter;
use truthrelay_api::{Cmd, cli::Cli, keygen, run};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt()
        .with_env_filter(
            EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")),
        )
        .init();

    let cli = Cli::parse();
    match cli.cmd {
        Cmd::Serve(opts) => run(opts).await?,
        Cmd::Keygen(opts) => keygen(&opts.name).await?,
    }
    Ok(())
}
