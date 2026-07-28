# TruthRelay web admin — Makefile
#
# Targets:
#   make dev        — Vite dev server with HMR (http://localhost:5173)
#   make build      — production build into dist/ (PWA precache)
#   make preview    — serve the production build locally
#   make test       — run the cross-language canonical+sign test
#   make docker     — build the nginx-served image (Dockerfile)
#   make fmt        — bunx prettier --write (if installed)
#   make clean      — remove dist/, dev-dist/, node_modules/

PKG := bun
API ?= http://localhost:8080

.PHONY: dev build preview test docker fmt clean

dev:
	VITE_API_URL=$(API) $(PKG) run dev

build:
	VITE_API_URL=$(API) $(PKG) run build

preview:
	$(PKG) run preview

test:
	VITE_API_URL=$(API) $(PKG) run scripts/canonical-test.ts

docker:
	docker build -t truthrelay-web:latest -f Dockerfile ..

fmt:
	$(PKG) x prettier --write .

clean:
	rm -rf dist dev-dist node_modules

install:
	$(PKG) install