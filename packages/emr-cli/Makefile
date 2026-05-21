DIST ?= dist
WHEEL_DIR ?= $(DIST)/wheels
EXECUTABLE ?= $(DIST)/emr-cli
export PEX_ROOT ?= $(CURDIR)/.pex-root

.PHONY: sync install test build-executable weep-auth weep-install lint check-style

# Install dependencies and the ``emr-cli`` console script into ``.venv``.
sync install:
	uv sync

# Self-contained executable (PEX). uv has no native single-file bundler; we invoke pex via uv.
# Output: ``dist/emr-cli`` (run directly; needs a Python 3.10–3.12 interpreter on PATH).
build-executable: sync
	@mkdir -p "$(WHEEL_DIR)"
	uv build --wheel --out-dir "$(WHEEL_DIR)"
	uv run pex "$(WHEEL_DIR)"/*.whl -c emr-cli -o "$(EXECUTABLE)" \
		--python="$(shell uv python find 3.12 2>/dev/null || uv python find)"
	@echo "Built $(EXECUTABLE)"

test:
	uv run pytest test/unit -v -W ignore::DeprecationWarning

# Authenticate with weep/consoleme and refresh credentials
weep-auth:
	./scripts/weep-auth.sh

# Install weep (idempotent)
weep-install:
	./scripts/install-weep.sh

lint:
	uv run ruff format src/ test/

check-style:
	uv run ruff format --check src/ test/
	uv run ruff check src/ test/
