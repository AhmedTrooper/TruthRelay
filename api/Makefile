# TruthRelay backend — Makefile
#
# Targets:
#   make dev        — run the server locally (cargo run -- serve)
#   make keygen     — mint a demo moderator keypair
#   make keygen NAME=alice — mint a keypair for moderator `alice`
#   make reset-db   — delete the local SQLite database
#   make test       — run the e2e shell smoke suite (server must be running)
#   make build      — release build into target/release/truthrelay
#   make docker     — build the api image (api/Dockerfile)
#   make fmt        — cargo fmt --all
#   make lint       — cargo clippy --all-targets -- -D warnings
#   make check      — cargo check --all-targets
#   make clean      — cargo clean

BIN := target/release/truthrelay
CARGO := cargo

.PHONY: dev keygen reset-db test build docker fmt lint check clean

dev:
	$(CARGO) run -- serve

keygen:
	$(CARGO) run -- keygen --name $(or $(NAME),demo)

reset-db:
	rm -f truthrelay.db truthrelay.db-shm truthrelay.db-wal
	@echo "✓ Local DB reset"

test:
	bash scripts/e2e.sh

build:
	$(CARGO) build --release
	@echo "✓ Built $(BIN)"

docker:
	docker build -t truthrelay-api:latest -f Dockerfile ..

fmt:
	$(CARGO) fmt --all

lint:
	$(CARGO) clippy --all-targets -- -D warnings

check:
	$(CARGO) check --all-targets

clean:
	$(CARGO) clean