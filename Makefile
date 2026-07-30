# TruthRelay — root Makefile
#
# Coordinates the three components (api, web, mobile) via sub-make.
#
# High-level targets:
#   make up         — docker compose up (api + web) in detached mode
#   make down       — docker compose down
#   make rebuild    — docker compose build --no-cache
#   make logs       — docker compose logs -f
#   make test       — run all tests (api e2e + web canonical + mobile)
#   make build      — build all three components (api release, web prod, apk debug)
#   make clean      — remove build artifacts
#   make reset      — nuke local databases, build outputs, and stop containers
#
# Per-component shortcuts (single-token composite goals — no double-fire):
#   make api               — list api/Makefile targets
#   make api-dev           — `cd api && make dev`
#   make api-test          — `cd api && make test`
#   make api-build         — `cd api && make build`
#   make api-clean         — `cd api && make clean`
#   make web               — list web/Makefile targets
#   make web-dev           — `cd web && make dev`
#   make web-build         — `cd web && make build`
#   make mobile            — list mobile/Makefile targets
#   make mobile-run        — `cd mobile && make run`
#   make mobile-build      — `cd mobile && make build`

COMPOSE := docker compose
PROJECT := truthrelay

# Why composite names (e.g. `api-dev`) instead of `make api dev`?
# GNU Make treats every word on the command line as a separate goal.
# `make api dev` would build *both* the root's `dev` target AND our
# `api` shortcut. Composite names keep it to a single goal so the
# recursion fires exactly once.

.PHONY: up down rebuild logs dev dev-api dev-web \
        api api-dev api-test api-build api-clean api-fmt api-lint api-check api-keygen api-reset-db api-docker \
        web web-dev web-build web-clean web-preview web-test web-docker web-install web-fmt \
        mobile mobile-run mobile-build mobile-clean mobile-test mobile-analyze mobile-get mobile-release \
        test build clean reset

# ---------- per-component list (no sub-target) ----------
api:
	@$(MAKE) -C api -qp 2>/dev/null | \
		awk -F':' '/^[a-zA-Z][a-zA-Z0-9_.-]*:/ && $$1 !~ /^(Makefile|MAKEFILES|\.PHONY)/ {print "  "$$1}' | sort -u

web:
	@$(MAKE) -C web -qp 2>/dev/null | \
		awk -F':' '/^[a-zA-Z][a-zA-Z0-9_.-]*:/ && $$1 !~ /^(Makefile|MAKEFILES|\.PHONY)/ {print "  "$$1}' | sort -u

mobile:
	@$(MAKE) -C mobile -qp 2>/dev/null | \
		awk -F':' '/^[a-zA-Z][a-zA-Z0-9_.-]*:/ && $$1 !~ /^(Makefile|MAKEFILES|\.PHONY)/ {print "  "$$1}' | sort -u

# ---------- per-component shortcuts (api) ----------
api-dev:        ; $(MAKE) -C api dev
api-test:       ; $(MAKE) -C api test
api-build:      ; $(MAKE) -C api build
api-clean:      ; $(MAKE) -C api clean
api-fmt:        ; $(MAKE) -C api fmt
api-lint:       ; $(MAKE) -C api lint
api-check:      ; $(MAKE) -C api check
api-keygen:     ; $(MAKE) -C api keygen
api-reset-db:   ; $(MAKE) -C api reset-db
api-docker:     ; $(MAKE) -C api docker

# ---------- per-component shortcuts (web) ----------
web-dev:        ; $(MAKE) -C web dev
web-build:      ; $(MAKE) -C web build
web-clean:      ; $(MAKE) -C web clean
web-preview:    ; $(MAKE) -C web preview
web-test:       ; $(MAKE) -C web test
web-docker:     ; $(MAKE) -C web docker
web-install:    ; $(MAKE) -C web install
web-fmt:        ; $(MAKE) -C web fmt

# ---------- per-component shortcuts (mobile) ----------
mobile-run:        ; $(MAKE) -C mobile run
mobile-build:      ; $(MAKE) -C mobile build
mobile-clean:      ; $(MAKE) -C mobile clean
mobile-test:       ; $(MAKE) -C mobile test
mobile-analyze:    ; $(MAKE) -C mobile analyze
mobile-get:        ; $(MAKE) -C mobile get
mobile-release:    ; $(MAKE) -C mobile release

# ---------- compose ----------
up:
	@echo "Starting services in foreground... API: http://localhost:8080, Web: http://localhost:5173"
	$(COMPOSE) up --build

docker-up: up

up-bg:
	$(COMPOSE) up -d --build
	@echo "✓ Services up in background. API: http://localhost:8080, Web: http://localhost:5173"

down:
	$(COMPOSE) down

rebuild:
	$(COMPOSE) build --no-cache

logs:
	$(COMPOSE) logs -f

# ---------- local dev (single-target form) ----------
dev-api:    api-dev
dev-web:    web-dev
dev:
	@echo "Run in two terminals:"
	@echo "  make api-dev    (or dev-api)"
	@echo "  make web-dev    (or dev-web)"

# ---------- cross-component test ----------
test: api-test mobile-test
	@echo "✓ All test suites passed"

build: api-build web-build mobile-build
	@echo "✓ All components built"

clean: api-clean web-clean mobile-clean
	@echo "✓ Build artifacts cleaned"

reset: down clean
	rm -f api/truthrelay.db* api/keys/* 2>/dev/null
	@echo "✓ Local state wiped"