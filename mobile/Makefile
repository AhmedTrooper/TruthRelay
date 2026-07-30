# TruthRelay mobile — Makefile
#
# Targets:
#   make get         — flutter pub get
#   make analyze     — flutter analyze (lint)
#   make test        — flutter test (canonical + sign tests)
#   make run         — flutter run on connected Android device
#   make build       — flutter build apk --debug
#   make release     — flutter build apk --release
#   make clean       — flutter clean
#
# Override the API URL with API=http://host:port
#   make run API=http://10.0.2.2:8080

API ?= http://10.0.2.2:8080
FLUTTER := flutter

.PHONY: get analyze test run build release clean

get:
	$(FLUTTER) pub get

analyze:
	$(FLUTTER) analyze

test:
	$(FLUTTER) test

run:
	$(FLUTTER) run --dart-define=TRUTHRELAY_API_URL=$(API)

build:
	$(FLUTTER) build apk --debug --dart-define=TRUTHRELAY_API_URL=$(API)

release:
	$(FLUTTER) build apk --release --dart-define=TRUTHRELAY_API_URL=$(API)

clean:
	$(FLUTTER) clean