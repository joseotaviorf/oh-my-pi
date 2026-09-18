###############################################################################
######################### CI Docker images ####################################
###############################################################################
# Set shell to bash for better compatibility with shell functions and RC file sourcing.
# The default /bin/sh can't properly source zsh-specific RC files (e.g. Oh My Zsh).
SHELL := /bin/bash

# PLATFORM: set to build for a specific arch (e.g. PLATFORM=linux/arm64).
# Omit for native-arch builds (the default).
PLATFORM ?=

.PHONY: build-ci-container-base
## Builds the ci-base image: python:3.12-slim-bookworm + git + make + uv.
## Used by lint, validation, and release CI steps.
## Requires GITHUB_TOKEN for private Git deps (BuildKit secret), same as build-devcontainer.
## Optional: PLATFORM=linux/arm64 for cross-arch builds.
build-ci-container-base:
	@echo "Building CI base image$(if $(PLATFORM), ($(PLATFORM)),)"
	@echo "=========="
	@echo ""
	@DOCKER_BUILDKIT=1 docker build \
	  $(if $(PLATFORM),--platform $(PLATFORM),) \
	  --target ci-base \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t bi-etl-ejuice-ci:base-latest \
	  -f .container/Dockerfile \
	  .
	@echo ""
	@echo "-> Image ready: bi-etl-ejuice-ci:base-latest"

.PHONY: build-ci-container-astro
## Builds the ci-astro image locally (linux/amd64 smoke-test only).
## ECR publish is CI-only via .woodpecker/containers.yml (amd64).
## Requires GITHUB_TOKEN for private Git deps (BuildKit secret), same as build-devcontainer.
build-ci-container-astro:
	@echo "Building CI Astro image (linux/amd64)"
	@echo "=========="
	@echo ""
	@DOCKER_BUILDKIT=1 docker build \
	  --target ci-astro \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t bi-etl-ejuice-ci:astro-latest \
	  -f .container/Dockerfile \
	  .
	@echo ""
	@echo "-> Image ready: bi-etl-ejuice-ci:astro-latest"

.PHONY: build-ci-container-astro-dind
## Builds the ci-astro-dind image locally (Debian DinD + Astro CLI).
## Requires GITHUB_TOKEN for private Git deps (BuildKit secret), same as build-devcontainer.
## Optional: PLATFORM=linux/amd64 for cross-arch builds; default is native arch.
build-ci-container-astro-dind:
	@echo "Building CI Astro DinD image$(if $(PLATFORM), ($(PLATFORM)),)"
	@echo "=========="
	@echo ""
	@DOCKER_BUILDKIT=1 docker build \
	  $(if $(PLATFORM),--platform $(PLATFORM),) \
	  --target ci-astro-dind \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t bi-etl-ejuice-ci:astro-dind-latest \
	  -f .container/Dockerfile \
	  .
	@echo ""
	@echo "-> Image ready: bi-etl-ejuice-ci:astro-dind-latest"

.PHONY: build-ci-container-jdk
## Builds the ci-jdk image: ci-base + openjdk-17-jre-headless.
## Used by test CI steps (PySpark needs a JVM).
## Requires GITHUB_TOKEN for private Git deps (BuildKit secret), same as build-devcontainer.
## Optional: PLATFORM=linux/arm64 for cross-arch builds.
build-ci-container-jdk:
	@echo "Building CI JDK image$(if $(PLATFORM), ($(PLATFORM)),)"
	@echo "=========="
	@echo ""
	@DOCKER_BUILDKIT=1 docker build \
	  $(if $(PLATFORM),--platform $(PLATFORM),) \
	  --target ci-jdk \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t bi-etl-ejuice-ci:jdk-latest \
	  -f .container/Dockerfile \
	  .
	@echo ""
	@echo "-> Image ready: bi-etl-ejuice-ci:jdk-latest"

.PHONY: build-ci-containers
## Builds CI images (ci-base + ci-astro + ci-astro-dind + ci-jdk) in one go.
## Requires GITHUB_TOKEN for private Git deps (same as build-devcontainer).
build-ci-containers: build-ci-container-base build-ci-container-astro build-ci-container-astro-dind build-ci-container-jdk

###############################################################################
######################### ECR publish (local) #################################
###############################################################################
# Publishes container images to ECR from a developer machine.
# Requires: `aws ecr get-login-password` to work (e.g. via `qli aws export`).
#
# Usage:
#   make publish-ci-base          # push ci-base (amd64)
#   make publish-ci-jdk           # push ci-jdk  (amd64)
#   make publish-devcontainer     # push devcontainer (arm64)
#   make publish-containers       # push all three
#
# ci-astro is published only by .woodpecker/containers.yml (not from local).
#
# SHA: first 7 chars of HEAD, used for the immutable tag.
# ENV: tag prefix (default: prod).

ECR_REPO   := 796143582747.dkr.ecr.us-east-1.amazonaws.com/quintoandar/bi-etl-ejuice
ECR_REGION := us-east-1
SHA7       := $(shell git rev-parse --short=7 HEAD)
ENV_PREFIX ?= prod

_ecr-login:
	@aws ecr get-login-password --region $(ECR_REGION) \
	  | docker login --username AWS --password-stdin \
	    796143582747.dkr.ecr.$(ECR_REGION).amazonaws.com

.PHONY: publish-ci-base
## Build and push ci-base image to ECR (amd64).
publish-ci-base: _ecr-login
	@echo "Publishing ci-base → $(ECR_REPO):$(ENV_PREFIX)-ci-base-latest"
	@DOCKER_BUILDKIT=1 docker build \
	  --platform linux/amd64 \
	  --target ci-base \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t $(ECR_REPO):$(ENV_PREFIX)-ci-base-latest \
	  -t $(ECR_REPO):$(ENV_PREFIX)-ci-base-$(SHA7) \
	  -f .container/Dockerfile \
	  .
	@docker push $(ECR_REPO):$(ENV_PREFIX)-ci-base-latest
	@docker push $(ECR_REPO):$(ENV_PREFIX)-ci-base-$(SHA7)
	@echo "-> Pushed $(ENV_PREFIX)-ci-base-latest + $(ENV_PREFIX)-ci-base-$(SHA7)"

.PHONY: publish-ci-jdk
## Build and push ci-jdk image to ECR (amd64).
publish-ci-jdk: _ecr-login
	@echo "Publishing ci-jdk → $(ECR_REPO):$(ENV_PREFIX)-ci-jdk-latest"
	@DOCKER_BUILDKIT=1 docker build \
	  --platform linux/amd64 \
	  --target ci-jdk \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t $(ECR_REPO):$(ENV_PREFIX)-ci-jdk-latest \
	  -t $(ECR_REPO):$(ENV_PREFIX)-ci-jdk-$(SHA7) \
	  -f .container/Dockerfile \
	  .
	@docker push $(ECR_REPO):$(ENV_PREFIX)-ci-jdk-latest
	@docker push $(ECR_REPO):$(ENV_PREFIX)-ci-jdk-$(SHA7)
	@echo "-> Pushed $(ENV_PREFIX)-ci-jdk-latest + $(ENV_PREFIX)-ci-jdk-$(SHA7)"

.PHONY: publish-devcontainer
## Build and push devcontainer image to ECR (arm64).
## Requires GITHUB_TOKEN env var for private Git deps.
publish-devcontainer: _ecr-login
	@echo "Publishing devcontainer → $(ECR_REPO):$(ENV_PREFIX)-devcontainer-latest"
	@DOCKER_BUILDKIT=1 docker build \
	  --platform linux/arm64 \
	  --target devcontainer \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t $(ECR_REPO):$(ENV_PREFIX)-devcontainer-latest \
	  -t $(ECR_REPO):$(ENV_PREFIX)-devcontainer-$(SHA7) \
	  -f .container/Dockerfile \
	  .
	@docker push $(ECR_REPO):$(ENV_PREFIX)-devcontainer-latest
	@docker push $(ECR_REPO):$(ENV_PREFIX)-devcontainer-$(SHA7)
	@echo "-> Pushed $(ENV_PREFIX)-devcontainer-latest + $(ENV_PREFIX)-devcontainer-$(SHA7)"

.PHONY: publish-containers
## Build and push all container images to ECR.
publish-containers: publish-ci-base publish-ci-jdk publish-devcontainer

###############################################################################
######################### Dev Container environment ###########################
###############################################################################
.PHONY: build-devcontainer
## Builds the devcontainer image locally (all stages in one go):
##   make build-devcontainer
## Builds ci-base → ci-jdk → devcontainer in a single Docker build.
## Requires GITHUB_TOKEN for private Git deps (BuildKit secret).
## Optional: PLATFORM=linux/arm64 for cross-arch builds.
build-devcontainer:
	@echo "Building dev container image$(if $(PLATFORM), ($(PLATFORM)),)"
	@echo "=========="
	@echo ""
	@DOCKER_BUILDKIT=1 docker build \
	  $(if $(PLATFORM),--platform $(PLATFORM),) \
	  --target devcontainer \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t bi-etl-ejuice:devcontainer-latest \
	  -f .container/Dockerfile \
	  .
	@echo ""
	@echo "-> Image ready: bi-etl-ejuice:devcontainer-latest"
	@echo "-> Open the project in Cursor and choose 'Reopen in Container'"

###############################################################################
###################### Package paths ##########################################
###############################################################################
# Compiler scripts root
COMPILER_SCRIPTS := packages/bietlejuice-compiler/scripts
export PYTHONPATH := .:packages/bietlejuice-compiler$(if $(PYTHONPATH),:$(PYTHONPATH),)

# CI/devcontainer images bake dbr at /opt/bietlejuice/venvs/dbr-16-4; local installs use envs/dbr-16-4/.venv.
ifeq ($(wildcard /opt/bietlejuice/venvs/dbr-16-4/bin/python3),)
DBR_UV_ENV :=
else
DBR_UV_ENV := UV_PROJECT_ENVIRONMENT=/opt/bietlejuice/venvs/dbr-16-4
endif

###############################################################################
###################### Local Airflow Docker environment #######################
###############################################################################
verbose ?=
ASTRO_LOCAL_IMAGE ?= bietlejuice-airflow:local

# resolve active shell rc file (zsh vs bash); caller may override via SHELL_RC env var.
SHELL_RC_EXPR := $${SHELL_RC:-$$(if [ "$$(basename "$$SHELL")" = "zsh" ]; then echo "$$HOME/.zshrc"; else echo "$$HOME/.bashrc"; fi)}

# load env vars with precedence: ~/.profile → ~/.bash_profile → shell rc → ./.env (last wins).
define load_env_vars
	SHELL_RC="$(SHELL_RC_EXPR)"; \
	set -a; \
	for f in "$$HOME/.profile" "$$HOME/.bash_profile" "$$SHELL_RC" ./.env; do \
	  [ -f "$$f" ] && . "$$f" 2>/dev/null || true; \
	done; \
	set +a
endef

# prompt for a missing credential and persist it into the active shell rc file.
# usage: $(call prompt_and_persist,VAR_NAME,prompt text)
define prompt_and_persist
	if [ -z "$${$(1)}" ]; then \
	  printf '$(2)'; \
	  read -r $(1); \
	  echo "export $(1)=$${$(1)}" >> "$$SHELL_RC"; \
	fi
endef

# Build the Astro image from repo root (same Dockerfile as CI). Astro CLI cannot
# build this Dockerfile from astro/ because COPY needs packages/ in context.
define build_astro_local_image
	echo "Building $(ASTRO_LOCAL_IMAGE) from repo root..."; \
	if [ -z "$${GITHUB_TOKEN}" ]; then \
	  echo "ERROR: GITHUB_TOKEN is required to build $(ASTRO_LOCAL_IMAGE)." >&2; \
	  exit 1; \
	fi; \
	export DOCKER_BUILDKIT=1; \
	docker build \
	  -f astro/Dockerfile \
	  --secret id=GITHUB_TOKEN,env=GITHUB_TOKEN \
	  -t $(ASTRO_LOCAL_IMAGE) \
	  . $(if $(verbose),,--quiet)
endef

# wait up to 150s for the Astro scheduler container to answer `airflow db check`.
define wait_for_scheduler
	echo "Waiting for Airflow to finish initializing..."; \
	SCHEDULER=$$(docker ps --filter "name=scheduler" --format "{{.Names}}" | grep -E "bietlejuice_|astro_" | head -1); \
	if [ -z "$$SCHEDULER" ]; then echo "ERROR: Scheduler container not found." >&2; exit 1; fi; \
	i=0; \
	while [ $$i -lt 30 ]; do \
	  docker exec $$SCHEDULER airflow db check > /dev/null 2>&1 && echo "Airflow is ready." && break; \
	  i=$$((i+1)); \
	  printf "  Attempt %d/30 — retrying in 5s...\n" $$i; \
	  sleep 5; \
	done; \
	docker exec $$SCHEDULER airflow db check > /dev/null 2>&1 || { echo "ERROR: Airflow did not become ready after 150s." >&2; exit 1; }
endef

.PHONY: setup-local-variables
## receives and sets up local shell variables to store token credentials used in the local Airflow environment.
## Variables are set either into ~/.zshrc or into ~/.bashrc, according to the default shell terminal used.
setup-local-variables:
	@echo "Setting up local variables"
	@echo "=========="
	@echo ""
	@$(load_env_vars); \
	ENV_FILE="$$(pwd)/.env"; \
	SOURCE_LINE="[ -f \"$$ENV_FILE\" ] && source \"$$ENV_FILE\""; \
	grep -qF "$$SOURCE_LINE" "$$SHELL_RC" 2>/dev/null || echo "$$SOURCE_LINE" >> "$$SHELL_RC"; \
	$(call prompt_and_persist,GITHUB_TOKEN,Enter your GitHub token: ); \
	$(call prompt_and_persist,DATABRICKS_TOKEN,Enter your Databricks token: ); \
	$(call prompt_and_persist,DATABRICKS_USERNAME,Enter your Databricks Username (email@quintoandar.com.br): )
	@echo "All variables set!"
	@echo "~> Restart your shell to apply changes!"

.PHONY: import-local-pools
import-local-pools:
	@echo "Importing local Airflow pools"
	@cd ./astro && bash import_local_pools.sh

.PHONY: import-local-aws-connection
import-local-aws-connection:
	@echo "Importing local Airflow AWS connection"
	@$(load_env_vars); \
	cd ./astro && bash import_local_aws_connection.sh

.PHONY: import-variables-and-connections
import-variables-and-connections:
	@echo "Import Variables and Connections"
	@$(load_env_vars); \
	cd ./astro; \
	sh import_conn_vars.sh

.PHONY: refresh-local-variables
## Regenerates astro/local_variables.json from forno Vault via qli (offline fallback seed).
## Primary local resolution is VaultBackend when VAULT_TOKEN is set (see run-local-environment).
refresh-local-variables:
	@python3 ./astro/scripts/refresh_local_variables.py

# Load the developer's short-lived Vault token from qli's cache into the shell
# so docker-compose.override.yml can inject VaultBackend kwargs. Soft-fail so
# offline fallback (local_variables.json import) still works without Vault —
# the override only enables VaultBackend when VAULT_TOKEN is non-empty.
# Capture output before eval: `eval "$$(cmd)"` would discard cmd's exit status.
define load_vault_token
	if [ -f ./astro/scripts/export_qli_vault_token.py ]; then \
	  vault_exports="$$(python3 ./astro/scripts/export_qli_vault_token.py)" && \
	    eval "$$vault_exports" || \
	    echo "WARNING: could not load Vault token (run: qli login -r -s vault). Falling back to local_variables.json seed." >&2; \
	fi
endef

.PHONY: build-astro-local-image
## Builds bietlejuice-airflow:local from repo root (astro/Dockerfile).
build-astro-local-image:
	@$(load_env_vars); \
	$(build_astro_local_image)

.PHONY: run-local-environment
## Starts local Airflow via astro/ using the production image (pre-built from repo root).
## Injects VAULT_TOKEN from qli so Airflow resolves variables via VaultBackend (forno path).
run-local-environment:
	@echo "Starting local Airflow environment (astro/)"
	@echo "=========="
	@echo ""
	@$(load_env_vars); \
	$(load_vault_token); \
	REPO_ROOT="$$(pwd)"; \
	export LOCAL_WORKSPACE_FOLDER="$${LOCAL_WORKSPACE_FOLDER:-$$REPO_ROOT}"; \
	$(build_astro_local_image); \
	cd ./astro; \
	astro dev start --image-name $(ASTRO_LOCAL_IMAGE) $(if $(verbose),--verbosity debug,); \
	if [ $$? -ne 0 ]; then \
	  echo ""; \
	  echo "Note: astro dev start health check timed out."; \
	  echo "This is expected inside a Docker-outside-Docker devcontainer: the Astro"; \
	  echo "webserver port is bound to 127.0.0.1 on the host daemon and is not"; \
	  echo "reachable via localhost from within the devcontainer network namespace."; \
	  echo "Bind mounts use LOCAL_WORKSPACE_FOLDER (host path); see .devcontainer/devcontainer.json."; \
	  echo "Verifying containers started correctly via Docker socket..."; \
	  astro dev ps | grep -q "running" || { echo "ERROR: Airflow containers are not running." >&2; exit 1; }; \
	  echo "All containers are running. Proceeding..."; \
	fi
	@$(wait_for_scheduler)
	@make import-local-pools
	-@make import-local-aws-connection
	@make import-variables-and-connections

.PHONY: restart-local-environment
restart-local-environment:
	@echo "Restart local Airflow environment (astro/)"
	@$(load_env_vars); \
	$(load_vault_token); \
	REPO_ROOT="$$(pwd)"; \
	export LOCAL_WORKSPACE_FOLDER="$${LOCAL_WORKSPACE_FOLDER:-$$REPO_ROOT}"; \
	$(build_astro_local_image); \
	cd ./astro; \
	astro dev restart --image-name $(ASTRO_LOCAL_IMAGE) $(if $(verbose),--verbose,); \
	if [ $$? -ne 0 ]; then \
	  echo ""; \
	  echo "Note: astro dev restart health check timed out."; \
	  echo "This is expected inside a Docker-outside-Docker devcontainer."; \
	  echo "Verifying containers started correctly via Docker socket..."; \
	  astro dev ps | grep -q "running" || { echo "ERROR: Airflow containers are not running." >&2; exit 1; }; \
	  echo "All containers are running. Proceeding..."; \
	fi
	@$(wait_for_scheduler)
	@make import-local-pools
	-@make import-local-aws-connection

.PHONY: stop-local-environment
stop-local-environment:
	@echo "Stop local Airflow environment"
	@cd ./astro; \
	astro dev stop

.PHONY: kill-local-environment
kill-local-environment:
	@echo "Delete local Airflow environment"
	@cd ./astro; \
	astro dev kill

###############################################################################
###################### Local environment S3 upload ############################
###############################################################################
.PHONY: upload-local-wheel
upload-local-wheel:
	@make build
	@uv run --project packages/bietlejuice-runtime python local/upload_local_whl_to_s3.py

.PHONY: upload-local-spark-jobs
upload-local-spark-jobs:
	@uv run --project packages/bietlejuice-runtime python local/upload_local_spark_jobs_to_s3.py databricks.s3.forno.data.quintoandar.com.br

.PHONY: upload-local-package
upload-local-package:
	@uv run --project packages/bietlejuice-runtime python local/upload_local_spark_jobs_to_s3.py
	@make build
	@uv run --project packages/bietlejuice-runtime python local/upload_local_whl_to_s3.py

.PHONY: upload-local-qube-jobs
upload-local-qube-jobs:
	@aws s3 sync packages/bietlejuice-runtime/src/bietlejuice/qube/jobs \
		s3://databricks.s3.forno.data.quintoandar.com.br/github-repos/bi-etl-ejuice/qube/jobs \
		--acl bucket-owner-full-control

.PHONY: upload-local-wheel-emr
## Overwrites Forno EMR bootstrap *-latest* wheels on the artifacts bucket (new clusters only).
## Requires EngineerFornoStagData_squad (not DataAndAnalyticsEMRUser_staff). See emr_init_script.sh.
upload-local-wheel-emr:
	@make build
	@RUNTIME=$$(ls -t dist/bietlejuice_runtime-*.whl 2>/dev/null | head -1); \
	CORE=$$(ls -t dist/bietlejuice_core-*.whl 2>/dev/null | head -1); \
	test -n "$$RUNTIME" && test -n "$$CORE" || { echo "ERROR: wheels missing under dist/; make build failed?" >&2; exit 1; }; \
	echo "Uploading $$CORE -> bi-etl-ejuice/bietlejuice_core-latest-py3-none-any.whl"; \
	aws s3 cp "$$CORE" s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/bietlejuice_core-latest-py3-none-any.whl \
		--acl bucket-owner-full-control; \
	echo "Uploading $$RUNTIME -> bi-etl-ejuice/bietlejuice_runtime-latest-py3-none-any.whl"; \
	aws s3 cp "$$RUNTIME" s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/bietlejuice_runtime-latest-py3-none-any.whl \
		--acl bucket-owner-full-control

.PHONY: upload-local-queries
upload-local-queries:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/upload_dag_packages_artifact_into_s3.py \
		databricks.s3.forno.data.quintoandar.com.br queries

.PHONY: upload-local-data-quality
upload-local-data-quality:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/upload_dag_packages_artifact_into_s3.py \
		databricks.s3.forno.data.quintoandar.com.br data_quality

.PHONY: upload-local-schemas
upload-local-schemas:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/upload_dag_packages_artifact_into_s3.py \
		databricks.s3.forno.data.quintoandar.com.br schemas

.PHONY: upload-local-metadata
## Upload dags/**/metadata/** into Forno DAG-packages S3 (needed by milestone_delta on EMR).
upload-local-metadata:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/upload_dag_packages_artifact_into_s3.py \
		databricks.s3.forno.data.quintoandar.com.br metadata

.PHONY: upload-local-init-scripts
upload-local-init-scripts:
	@aws s3 cp $(COMPILER_SCRIPTS)/init_script.sh \
		s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/init_script.sh \
		--acl bucket-owner-full-control
	@aws s3 cp $(COMPILER_SCRIPTS)/emr_init_script.sh \
		s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/emr_init_script.sh \
		--acl bucket-owner-full-control
	@aws s3 cp $(COMPILER_SCRIPTS)/emr_custom_libraries.py \
		s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/emr_custom_libraries.py \
		--acl bucket-owner-full-control
	@aws s3 cp $(COMPILER_SCRIPTS)/init_script_anonymization.sh \
		s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/init_script_anonymization.sh \
		--acl bucket-owner-full-control
	@aws s3 cp $(COMPILER_SCRIPTS)/wonka/install_pex_generic.sh \
		s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/install_pex_generic.sh \
		--acl bucket-owner-full-control
	@aws s3 cp $(COMPILER_SCRIPTS)/wonka/get_credentials_from_vault.sh \
		s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/get_credentials_from_vault.sh \
		--acl bucket-owner-full-control
	@aws s3 cp $(COMPILER_SCRIPTS)/wonka/configure_spark.sh \
		s3://artifacts.s3.forno.data.quintoandar.com.br/bi-etl-ejuice/configure_spark.sh \
		--acl bucket-owner-full-control
	@aws s3 cp $(COMPILER_SCRIPTS)/sedona/sedona-init.sh \
		s3://artifacts.s3.forno.data.quintoandar.com.br/sedona/sedona-init.sh \
		--acl bucket-owner-full-control

.PHONY: upload-forno-release
## Full local Forno release: builds wheel and uploads all artifacts to Forno S3 (mirrors release.yml forno steps).
upload-forno-release:
	@make upload-local-package
	@make upload-local-wheel-emr
	@make upload-local-queries
	@make upload-local-metadata
	@make upload-local-data-quality
	@make upload-local-schemas
	@make upload-local-qube-jobs
	@make upload-local-init-scripts

###############################################################################
###################### Local Python environment ###############################
###############################################################################
.PHONY: build
## build wheels for Databricks-deployed packages (bietlejuice-core + bietlejuice-runtime)
build:
	@echo ""
	@echo "Building wheels"
	@echo "=========="
	@echo ""
	@uv build packages/bietlejuice-core --out-dir dist/
	@rm -rf build/dags_yaml
	@mkdir -p build/dags_yaml
	@rsync -a --prune-empty-dirs \
		--include='*/' \
		--include='*_api_declaration.yml' \
		--include='*_api_declaration.yaml' \
		--include='gsheets_*_declaration.yml' \
		--include='gsheets_*_declaration.yaml' \
		--include='*_conf.yml' \
		--include='*_conf.yaml' \
		--include='gsheets_files.yaml' \
		--exclude='*' \
		dags/ build/dags_yaml/
	@touch build/dags_yaml/__init__.py
	@uv build --wheel packages/bietlejuice-runtime --out-dir dist/

.PHONY: install
## install all package dependencies via uv
## Workspace members (shared uv.lock): core, airflow, operators, plugins, compiler,
## emr-cli — see root pyproject.toml.
## Runtime is standalone (not a workspace member). Its venv holds broad-version deps for
## lint/type-check; DBR-pinned libs live under packages/bietlejuice-runtime/envs/.
## We sync envs/dbr-16-4 by default so `make unit-tests` works out of the box.
## Switch to another DBR's env with `make sync-dbr DBR=12.2|13.3`.
## dags/ is not uv-managed; use `make check-style-dags`. Packages + compiler scripts: `make check-style`.
install:
	@echo ""
	@echo "Installing all packages"
	@echo "=========="
	@echo ""
	@uv sync --directory packages/bietlejuice-core
	@uv sync --directory packages/bietlejuice-airflow
	@uv sync --directory packages/bietlejuice-airflow-operators
	@uv sync --directory packages/bietlejuice-airflow-plugins
	@uv sync --directory packages/bietlejuice-compiler
	@uv sync --directory packages/emr-cli
	@# `env -u UV_PROJECT_ENVIRONMENT` is a no-op locally but inside the devcontainer
	@# it stops uv from redirecting runtime's / the env's .venv into the shared
	@# workspace venv at /home/vscode/.venv (which would clobber it).
	@env -u UV_PROJECT_ENVIRONMENT uv sync --directory packages/bietlejuice-runtime
	@env -u UV_PROJECT_ENVIRONMENT uv sync --directory packages/bietlejuice-runtime/envs/dbr-16-4

DBR ?= 16.4
.PHONY: sync-dbr
## sync the runtime DBR env to a specific DBR (DBR=12.2|13.3|16.4, default 16.4).
## Each sub-project under packages/bietlejuice-runtime/envs/dbr-X-Y is a tiny
## "shim" pyproject whose only job is to produce a venv that mirrors that DBR:
## the Python version, the bundled libs (numpy, pandas, pyarrow, psycopg2, ...),
## plus bietlejuice-runtime + bietlejuice-core in editable mode. uv resolves
## one DBR per .venv, so there is no cross-DBR conflict.
## Point your IDE at envs/dbr-X-Y/.venv/bin/python after running this.
sync-dbr:
	@echo ""
	@echo "Syncing bietlejuice-runtime env for DBR $(DBR)"
	@echo "=========="
	@echo ""
	@case "$(DBR)" in \
	  12.2|13.3|16.4) ;; \
	  *) echo "ERROR: Unknown DBR: $(DBR). Supported: 12.2, 13.3, 16.4" >&2 && exit 1 ;; \
	esac
	@# See `install` target for why we unset UV_PROJECT_ENVIRONMENT.
	@env -u UV_PROJECT_ENVIRONMENT uv sync --directory "packages/bietlejuice-runtime/envs/dbr-$$(echo $(DBR) | tr . -)"

###############################################################################
###################### Style handling #########################################
###############################################################################
##
RUFF_UV := uv run --project packages/bietlejuice-compiler
RUFF_EXCLUDE := packages/bietlejuice-compiler/scripts/ci_cd/airflow_dag_builder/__dags_template__.py
RUFF_FORMAT_PATHS := \
	packages/bietlejuice-core/src \
	packages/bietlejuice-core/test \
	packages/bietlejuice-airflow/src \
	packages/bietlejuice-airflow/test \
	packages/bietlejuice-airflow-operators/src \
	packages/bietlejuice-airflow-operators/test \
	packages/bietlejuice-airflow-plugins/src \
	packages/bietlejuice-airflow-plugins/test \
	packages/bietlejuice-runtime/src \
	packages/bietlejuice-runtime/test \
	packages/bietlejuice-compiler/src \
	packages/bietlejuice-compiler/test \
	packages/bietlejuice-compiler/scripts \
	packages/emr-cli/src \
	packages/emr-cli/test
RUFF_CHECK_PATHS := $(RUFF_FORMAT_PATHS)
RUFF_DAGS_PATHS := dags/

.PHONY: lint
lint:
	@echo ""
	@echo "Running Ruff format on packages + compiler scripts"
	@echo "=========="
	@echo ""
	@$(RUFF_UV) ruff format --exclude $(RUFF_EXCLUDE) $(RUFF_FORMAT_PATHS)

.PHONY: lint-dags
lint-dags:
	@echo ""
	@echo "Running Ruff format on dags/"
	@echo "=========="
	@echo ""
	@$(RUFF_UV) ruff format $(RUFF_DAGS_PATHS)

.PHONY: check-style
## Ruff format check + lint on packages and compiler scripts
check-style:
	@echo ""
	@echo "Running Check Style (packages + compiler scripts)"
	@echo "=========="
	@echo ""
	@$(RUFF_UV) ruff format --check --exclude $(RUFF_EXCLUDE) $(RUFF_CHECK_PATHS)
	@$(RUFF_UV) ruff check --exclude $(RUFF_EXCLUDE) $(RUFF_CHECK_PATHS)

.PHONY: check-style-dags
## Ruff format check + lint on dags/ (Woodpecker: check-style-dags-python)
check-style-dags:
	@echo ""
	@echo "Running Check Style (dags/)"
	@echo "=========="
	@echo ""
	@$(RUFF_UV) ruff format --check $(RUFF_DAGS_PATHS)
	@$(RUFF_UV) ruff check $(RUFF_DAGS_PATHS)

.PHONY: validate-py39-runtime-typing
## Fail on PEP 604 type annotations unsafe at import time on EMR Python 3.9
validate-py39-runtime-typing:
	@python3 scripts/validate_py39_runtime_typing.py

.PHONY: fix-style
## autofix lint issues on packages + compiler scripts (same scope as check-style)
fix-style:
	@echo ""
	@echo "Running Style Fix (packages + compiler scripts, ruff --fix)"
	@echo "=========="
	@echo ""
	@$(RUFF_UV) ruff check --fix --exclude $(RUFF_EXCLUDE) $(RUFF_CHECK_PATHS)

.PHONY: fix-style-dags
## autofix lint issues on dags/ (same scope as check-style-dags)
fix-style-dags:
	@echo ""
	@echo "Running Style Fix (dags/, ruff --fix)"
	@echo "=========="
	@echo ""
	@$(RUFF_UV) ruff check --fix $(RUFF_DAGS_PATHS)

.PHONY: type-check
## run ty type checker on packages/*/src (core, airflow, runtime, compiler, emr-cli; informative; CI failure:ignore)
type-check:
	@echo ""
	@echo "Type Check"
	@echo "=========="
	@echo ""
	@uv run --directory packages/bietlejuice-core     ty check src/
	@uv run --directory packages/bietlejuice-airflow  ty check src/
	@uv run --directory packages/bietlejuice-runtime  ty check src/
	@uv run --directory packages/bietlejuice-compiler ty check src/
	@# emr-cli has no workspace `ty` dev dep; run via compiler project (same as Ruff).
	@$(RUFF_UV) ty check packages/emr-cli/src

.PHONY: lint-sql
## run sqlfluff to fix SQL style in dags/
lint-sql:
	@echo ""
	@echo "Running SQL lint"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler sqlfluff fix dags/

.PHONY: check-sql
## check SQL style with sqlfluff in dags/
check-sql:
	@echo ""
	@echo "Running SQL Check Style"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler sqlfluff lint dags/

###############################################################################
###################### Tests commands #########################################
###############################################################################

.PHONY: tests
## run all tests across all packages (unit-tests + unit-tests-dags)
tests:
	@make unit-tests
	@make unit-tests-dags

.PHONY: unit-tests
## Runtime tests run from the dbr-16-4 env's venv so the resolved
## numpy/pandas/pydantic/... versions match what production runs on DBR 16.4.
## Pytest still reads its config from packages/bietlejuice-runtime/pyproject.toml
## because that is the cwd we hand to it. PYSPARK_PYTHON/PYSPARK_DRIVER_PYTHON
## are pinned to the env's interpreter so Spark workers don't pick up some
## unrelated `python3` from PATH (e.g. a system 3.14) and crash with
## PYTHON_VERSION_MISMATCH.
unit-tests:
	@echo ""
	@echo "Unit Tests"
	@echo "=========="
	@echo ""
	@# Woodpecker runs setup and unit-tests in separate steps; only the git checkout is
	@# shared, not /opt/bietlejuice/venvs/workspace. Sync here so workspace members (core
	@# tests import airflow from bietlejuice-airflow) resolve against the full workspace.
	@# Use --directory (not --package) so pytest rootdir/testpaths stay per-package; --package
	@# runs from the repo root and collects runtime/dag tests without the dbr-16-4 venv.
	@uv sync
	@uv run --directory packages/bietlejuice-core     pytest -W ignore::DeprecationWarning
	@uv run --directory packages/bietlejuice-airflow  pytest -W ignore::DeprecationWarning
	@uv run --directory packages/bietlejuice-airflow-operators pytest -W ignore::DeprecationWarning
	@uv run --directory packages/bietlejuice-airflow-plugins pytest -W ignore::DeprecationWarning
	@# Astro env guards (airflowignore dual-syntax, parse pre-warm, alias-batching patch).
	@# Runs from the root workspace env (airflow comes in via bietlejuice-airflow).
	@# The fork/parse test self-skips unless `make create-dag-files` has generated
	@# the DAG stubs it parses (gitignored, so absent in CI's uv-sync-only step).
	@uv run pytest astro/tests -W ignore::DeprecationWarning
	@cd packages/bietlejuice-runtime && DBR_PY=$$($(DBR_UV_ENV) uv run --project envs/dbr-16-4 python -c "import sys; print(sys.executable)") && PYSPARK_PYTHON=$$DBR_PY PYSPARK_DRIVER_PYTHON=$$DBR_PY $(DBR_UV_ENV) uv run --project envs/dbr-16-4 pytest test/unit -W ignore::DeprecationWarning
	@uv run --directory packages/bietlejuice-compiler pytest -W ignore::DeprecationWarning
	@uv run --directory packages/emr-cli pytest -W ignore::DeprecationWarning

.PHONY: unit-tests-dags
## DAG spark-job tests under packages/bietlejuice-runtime/test/dags.
## Each top-level domain runs in its own pytest process so conftest sys.modules mocks
## (e.g. agents, cross) cannot leak into people/tech_platform suites.
## Nested domains (tech_platform, mlops, for_rent, people) run each child dir
## separately so a sibling job's pyspark stub cannot clobber a real-Spark suite.
unit-tests-dags:
	@echo ""
	@echo "DAG spark job tests (runtime/test/dags)"
	@echo "=========="
	@echo ""
	@uv sync
	@cd packages/bietlejuice-runtime && DBR_PY=$$($(DBR_UV_ENV) uv run --project envs/dbr-16-4 python -c "import sys; print(sys.executable)") && \
	 export PYSPARK_PYTHON=$$DBR_PY PYSPARK_DRIVER_PYTHON=$$DBR_PY PYTHONPATH=src:../.. && \
	 FAILED=0 && \
	 _run_dag_suite() { \
	   local dir="$$1"; \
	   if [ ! -d "$$dir" ]; then return 0; fi; \
	   if ! find "$$dir" -name 'test_*.py' -print -quit | grep -q .; then \
	     echo "Skipping $$dir (no test_*.py)"; return 0; \
	   fi; \
	   echo "" && echo "--- $$dir ---" && \
	   $(DBR_UV_ENV) uv run --project envs/dbr-16-4 pytest "$$dir" -W ignore::DeprecationWarning || FAILED=1; \
	 }; \
	 for suite in test/dags/*/; do \
	   if [ "$$suite" = "test/dags/tech_platform/" ] || [ "$$suite" = "test/dags/mlops/" ] || [ "$$suite" = "test/dags/for_rent/" ] || [ "$$suite" = "test/dags/people/" ]; then \
	     for nested in "$$suite"*/; do _run_dag_suite "$$nested"; done; \
	   else \
	     _run_dag_suite "$$suite"; \
	   fi; \
	 done && \
	 [ $$FAILED -eq 0 ]

.PHONY: integration-tests
## run integration tests
integration-tests:
	@echo ""
	@echo "Integration Tests"
	@echo "================="
	@echo ""
	@uv sync
	@# --no-cov: unit-tests-python already collects integration coverage in parallel CI;
	@# sharing .coverage between steps causes intermittent sqlite combine failures.
	@uv run --directory packages/bietlejuice-core pytest test/integration -W ignore::DeprecationWarning --no-cov

.PHONY: files-validation
files-validation:
	@echo ""
	@echo "Validation Files Tests"
	@echo "=========="
	@echo ""
	@uv run --directory packages/bietlejuice-compiler pytest test/unit/files_validation/

.PHONY: core-model-tests
## run core model DAG tests with coverage check (CI/CD only - only runs if core model changes detected)
## Same rationale as unit-tests: runs from the dbr-16-4 env's venv to mirror prod versions.
## PYSPARK_PYTHON pinning matches unit-tests; see comment there.
core-model-tests:
	@echo ""
	@echo "Checking for core model changes"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@cd packages/bietlejuice-runtime && DBR_PY=$$($(DBR_UV_ENV) uv run --project envs/dbr-16-4 python -c "import sys; print(sys.executable)") && PYSPARK_PYTHON=$$DBR_PY PYSPARK_DRIVER_PYTHON=$$DBR_PY $(DBR_UV_ENV) uv run --project envs/dbr-16-4 pytest -W ignore::DeprecationWarning test/core_model_dags/ src/bietlejuice/base/core_models/

.PHONY: core-model-coverage
## check test coverage for core model source code (CI/CD only - only runs if core model changes detected)
core-model-coverage:
	@echo ""
	@echo "Checking for core model changes"
	@echo "=========="
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/core_models/check_core_model_changes.py -b "$(CI_COMMIT_BRANCH)" -v && exit 0 || \
		(echo "" && \
		 echo "Core Model Test Coverage Check" && \
		 echo "==========" && \
		 echo "" && \
		 uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/core_models/check_core_model_coverage.py -v)

###############################################################################
###################### Validations commands ###################################
###############################################################################
.PHONY: transcript-sql-files
## transcript new/modified SQL files from Trino to Databricks syntax
transcript-sql-files:
	@echo ""
	@echo "Transcripting SQL files from Trino to Databricks syntax"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/sql_transcript.py --mode git-diff --from-branch origin/master --to-branch HEAD

.PHONY: validate-dags-dependencies
validate-dags-dependencies:
	@echo ""
	@echo "Validating DAGs dependencies"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_dags_dependencies.py $(if $(domain),--domain $(domain),)

.PHONY: validate-dependency-file-correctness
## validates the correctness of the dags/dependencies.yaml file, according to the FileDependencyGenerator.
validate-dependency-file-correctness:
	@echo ""
	@echo "Validating correctness of dags/dependencies.yaml file"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/dependency_handling/validate_dependency_file_correctness.py

.PHONY: validate-no-new-cyclic-dependencies
## fails when a change introduces a DAG dependency cycle that does not exist on master. A cycle makes
## the generator delete every dependency between the DAGs involved, silently losing their ordering.
validate-no-new-cyclic-dependencies:
	@echo ""
	@echo "Validating that no new cyclic DAG dependencies were introduced"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/dependency_handling/validate_no_new_cyclic_dependencies.py

.PHONY: validate-no-new-late-schedule-dependencies
## fails when a change adds a dataset wait on a DAG whose first daily run is later than
## any pre-existing upstream (e.g. noon CDC like nazare delaying morning DW DAGs).
## Woodpecker runs this on PRs with failure: ignore so release is not blocked.
validate-no-new-late-schedule-dependencies:
	@echo ""
	@echo "Validating that no new late-schedule DAG dependencies were introduced"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/dependency_handling/validate_no_new_late_schedule_dependencies.py

level ?= warning
domain ?=
paths ?=
export ENVIRONMENT ?= forno
.PHONY: validate-dag-declaration-files
## validates the content of DAG declaration YAML files, returning which keys of which files are not following requirements.
## May receive an optional `level={level}` argument to declare the expected logging level of the validation.
validate-dag-declaration-files:
	@echo ""
	@echo "Validating DAG declaration files"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/validate_dag_declaration_files.py -l $(level) $(if $(domain),--domain $(domain),)

DAG_PATH ?= dags/
.PHONY: extract-cluster-validation-files validate-cluster-validation-extract-check validate-cluster-validation-files audit-cluster-instance-families
## Regenerate *_cluster.yml prod (verbatim) and validation blocks under DAG_PATH (default: dags/).
## Optional: SOURCE_REF=<git-ref> when cluster: was already removed from declarations.
## Optional: STRIP_DECLARATION=1 to move cluster: out of *_declaration.yml into *_cluster.yml.
extract-cluster-validation-files:
	@echo ""
	@echo "Extracting cluster validation files under $(DAG_PATH)"
	@echo "=========="
	@echo ""
	@ENVIRONMENT=prod uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/extract_cluster_validation_files.py $(DAG_PATH) $(if $(SOURCE_REF),--source-ref $(SOURCE_REF),) $(if $(STRIP_DECLARATION),--strip-declaration,)

## CI check: *_cluster.yml must match generator output (entire dags/ tree by default).
validate-cluster-validation-extract-check:
	@echo ""
	@echo "Validating cluster YAML matches generator output"
	@echo "=========="
	@echo ""
	@ENVIRONMENT=prod uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/extract_cluster_validation_files.py dags/ --check

## Extract --check then instance-family audit (audit runs even if extract fails).
validate-cluster-validation-files:
	@echo ""
	@echo "Validating cluster validation files"
	@echo "=========="
	@echo ""
	@EXIT=0; \
	$(MAKE) validate-cluster-validation-extract-check || EXIT=1; \
	$(MAKE) audit-cluster-instance-families || EXIT=1; \
	exit $$EXIT

## Audit *_cluster.yml driver/worker overrides for generation-family drift vs presets.
audit-cluster-instance-families:
	@echo ""
	@echo "Auditing cluster instance-family overrides"
	@echo "=========="
	@echo ""
	@ENVIRONMENT=prod uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/validation/audit_cluster_instance_families.py dags/ --check

## validates if the DAGs are using our current standards, such as using DAG Builder or CDC.
validate-dags-up-to-standard:
	@echo ""
	@echo "Validating DAG declaration files"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/dag_standard_validation/validate_dags_following_current_standards.py $(if $(domain),--domain $(domain),)

.PHONY: validate-jiraops-routine-mute-list
validate-jiraops-routine-mute-list:
	@echo ""
	@echo "Validating jiraops_mute_list.yml"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/jiraops/validate_jiraops_routine_mute_list.py

.PHONY: validate-jiraops-routine-exceptions
validate-jiraops-routine-exceptions:
	@echo ""
	@echo "Validating jiraops_routine_exceptions.yml"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/jiraops/validate_jiraops_routine_exceptions.py

.PHONY: sync-jiraops-routine-mute-list
sync-jiraops-routine-mute-list:
	@echo ""
	@echo "Syncing Jira Ops routine mute list"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/jiraops/sync_jiraops_routine_mute_list.py

.PHONY: validate-metadata-files-content
validate-metadata-files-content:
	@echo ""
	@echo "Validating if new/modified metadata files follow the metadata file schema"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/governance_metadata_validation/validate_metadata_files_content.py -b "$(CI_COMMIT_BRANCH)" -v $(if $(domain),--domain $(domain),)

.PHONY: sync-domain-allowlist
sync-domain-allowlist:
	@echo ""
	@echo "Syncing the metadata domain allowlist (domains.yml) into the Yamale schemas"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/governance_metadata_validation/sync_domain_allowlist.py

.PHONY: validate-domain-allowlist-sync
validate-domain-allowlist-sync:
	@echo ""
	@echo "Checking the Yamale schemas are in sync with the metadata domain allowlist"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/governance_metadata_validation/sync_domain_allowlist.py --check

.PHONY: validate-metadata-files-exist
validate-metadata-files-exist:
	@echo ""
	@echo "Validating if new/modified query files have corresponding metadata file defined"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/governance_metadata_validation/validate_metadata_files_exist.py -b "$(CI_COMMIT_BRANCH)" -v $(if $(domain),--domain $(domain),)


.PHONY: validate-datahub-context-entities
## Deterministic, offline gate for changed DataHub context entity .md files
## (docs/llm_context/{domain,metric}_entities). Reuses the authoritative
## parser+validator; needs NO DataHub/LLM credentials. Runs on PRs (see
## .woodpecker/validations.yml) so a malformed entity doc is blocked before it
## reaches master and the DataHub publish step.
validate-datahub-context-entities:
	@echo ""
	@echo "Validating changed DataHub context entity docs (domain + metric)"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run python dags/governance/datahub_business_context/validate_datahub_context_entities.py --changed-only -b "$(CI_COMMIT_BRANCH)"

.PHONY: validate-entity-golden-queries-metadata
## Validate golden-query SQL in changed entity docs against repo metadata YAML
## under dags/**/metadata (tables + documented columns). Does not execute SQL on
## Trino (see validate_entity_golden_queries_metadata.py).
validate-entity-golden-queries-metadata:
	@echo ""
	@echo "Validating golden queries in changed entity docs (repo metadata gate)"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python dags/governance/datahub_business_context/validate_entity_golden_queries_metadata.py --changed-only -b "$(CI_COMMIT_BRANCH)"

.PHONY: validate-llm-context-dag-impact
## Block DAG metadata YAML changes that remove or rename columns still used in
## docs/llm_context golden queries; warn when columns are only added.
validate-llm-context-dag-impact:
	@echo ""
	@echo "Validating llm_context golden-query impact of changed DAG metadata YAML files"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python dags/governance/datahub_business_context/validate_llm_context_dag_impact.py --changed-only -b "$(CI_COMMIT_BRANCH)"

.PHONY: validate-fair-metadata
validate-fair-metadata:
	@echo ""
	@echo "Validating FAIR metadata (F2-01 table + F2-02 column substantive descriptions) on changed clean+ YAML"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-runtime python -m bietlejuice.governance.fairness_assessment.validate_metadata_cli -b "$(CI_COMMIT_BRANCH)"

.PHONY: audit-fair-metadata-scope
## Run Gates A/B on the full user-requested scope (not PR diff). Pass exactly one of: domain=, owner=, fqn=, dag=
audit-fair-metadata-scope:
	@echo ""
	@echo "Auditing FAIR metadata scope (Gates A/B)"
	@echo "=========="
	@echo ""
	@if [ -n "$(domain)" ]; then \
		uv run --project packages/bietlejuice-runtime python -m bietlejuice.governance.fairness_assessment.validate_metadata_cli --audit --domain "$(domain)" $(if $(owner),--owner "$(owner)",); \
	elif [ -n "$(owner)" ]; then \
		uv run --project packages/bietlejuice-runtime python -m bietlejuice.governance.fairness_assessment.validate_metadata_cli --audit --owner "$(owner)"; \
	elif [ -n "$(fqn)" ]; then \
		uv run --project packages/bietlejuice-runtime python -m bietlejuice.governance.fairness_assessment.validate_metadata_cli --audit --fqn "$(fqn)"; \
	elif [ -n "$(dag)" ]; then \
		uv run --project packages/bietlejuice-runtime python -m bietlejuice.governance.fairness_assessment.validate_metadata_cli --audit --dag "$(dag)"; \
	else \
		echo "Error: pass scope via domain=, owner=, fqn=, or dag="; exit 1; \
	fi

.PHONY: validate-lineage-consistency
validate-lineage-consistency:
	@echo ""
	@echo "Validating if metadata files are consistent with their SQL queries"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/governance_metadata_validation/validate_lineage_consistency.py -b "$(CI_COMMIT_BRANCH)" -v $(if $(domain),--domain $(domain),)

.PHONY: validate-lineage-consistency-all
## validates that all metadata files are consistent with SQL queries (local development)
validate-lineage-consistency-all:
	@echo ""
	@echo "Validating all metadata files for consistency with SQL queries"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/governance_metadata_validation/validate_lineage_consistency.py -a

.PHONY: validate-core-model-schemas
## validates that all core model tables have corresponding schema files (CI/CD only)
validate-core-model-schemas:
	@echo ""
	@echo "Validating if new/modified core model tables have corresponding schema files"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_core_model_schemas.py -b "$(CI_COMMIT_BRANCH)" -v

.PHONY: validate-core-model-schema-content
## validates that core model schema files have correct content structure (CI/CD only)
validate-core-model-schema-content:
	@echo ""
	@echo "Validating if new/modified core model schema files have correct content structure"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_core_model_schema_content.py -b "$(CI_COMMIT_BRANCH)" -v

.PHONY: validate-core-model-schemas-all
## validates that all core model tables have corresponding schema files (local development)
validate-core-model-schemas-all:
	@echo ""
	@echo "Validating all core model schema files"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_core_model_schemas.py -a

.PHONY: validate-core-model-schema-content-all
## validates that all core model schema files have correct content structure (local development)
validate-core-model-schema-content-all:
	@echo ""
	@echo "Validating all core model schema file content"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_core_model_schema_content.py -a

.PHONY: validate-queries-datalake-path-import
## ensures QUERIES_DATALAKE_PATH is not imported from bietlejuice.base.db (use bietlejuice.base.paths)
validate-queries-datalake-path-import:
	@echo ""
	@echo "Validating QUERIES_DATALAKE_PATH import (not from bietlejuice.base.db)"
	@echo "=========="
	@echo ""
	@python3 $(COMPILER_SCRIPTS)/ci_cd/validate_queries_datalake_path_import.py

.PHONY: validate-source-layer-policy
## validates that changed DAGs only reference allowed source layers (CI/CD; PR-scoped; declaration-driven)
## Profiles: packages/bietlejuice-compiler/scripts/ci_cd/source_layer_validation/profiles/*.yml (default: dags)
validate-source-layer-policy:
	@echo ""
	@echo "Validating source-layer policy for changed DAGs"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/source_layer_validation/validate_source_layer_policy.py --profile dags -b "$(CI_COMMIT_BRANCH)" $(if $(domain),--domain $(domain),)

.PHONY: validate-source-layer-policy-all
## validates all DAGs under dags/ against source-layer policy (local audit; warnings-only for existing violations)
validate-source-layer-policy-all:
	@echo ""
	@echo "Validating source-layer policy for all DAGs under dags/"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/source_layer_validation/validate_source_layer_policy.py --profile dags -a

.PHONY: validate-source-layer-policy-all-core
## same as validate-source-layer-policy-all but only dags/core/ (faster local audit)
validate-source-layer-policy-all-core:
	@echo ""
	@echo "Validating source-layer policy for all core DAGs"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/source_layer_validation/validate_source_layer_policy.py --profile dags -a --core-only

.PHONY: validate-databricks-sql-constructs
## Fail if new/changed SQL files introduce Databricks-only constructs or trailing SELECT commas incompatible with EMR Spark 3.5
validate-databricks-sql-constructs:
	@echo ""
	@echo "Validating SQL for Databricks-specific constructs (EMR compatibility)"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_databricks_sql_constructs.py -b "$(CI_COMMIT_BRANCH)"

.PHONY: validate-databricks-sql-constructs-all
## Scan all .sql files under dags/ for Databricks-only constructs (local audit)
validate-databricks-sql-constructs-all:
	@echo ""
	@echo "Scanning all SQL files for Databricks-specific constructs"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_databricks_sql_constructs.py -a

.PHONY: validate-no-new-databricks-clusters
## Fail if a PR introduces Databricks prod runtime (new DAG or EMR→Databricks)
validate-no-new-databricks-clusters:
	@echo ""
	@echo "Validating no new Databricks production cluster introductions"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_no_new_databricks_clusters.py -b "$(CI_COMMIT_BRANCH)"

.PHONY: validate-no-new-databricks-clusters-all
## List all DAGs with Databricks prod clusters (local audit)
validate-no-new-databricks-clusters-all:
	@echo ""
	@echo "Listing DAGs with Databricks production runtime"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_no_new_databricks_clusters.py -a

.PHONY: validate-dag-builds
## Fail if a changed DAG cannot be built with prod config (parse-time gate)
validate-dag-builds: generate-query-manifests generate-metadata-manifests generate-data-quality-manifests
	@echo ""
	@echo "Validating changed DAGs build with prod config"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/validate_dag_builds.py -b "$(CI_COMMIT_BRANCH)"

.PHONY: validate-dag-builds-all
## Build every DAG with prod config (local audit)
validate-dag-builds-all: generate-query-manifests generate-metadata-manifests generate-data-quality-manifests
	@echo ""
	@echo "Building all DAGs with prod config"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/validate_dag_builds.py -a

.PHONY: validate-emr-runtime-clients
## Fail if a newly added spark job bypasses SparkClient/BaseDBUtils/dual-catalog registration
validate-emr-runtime-clients:
	@echo ""
	@echo "Validating new spark jobs use the bietlejuice dual-runtime clients"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_emr_runtime_clients.py -b "$(CI_COMMIT_BRANCH)"

.PHONY: validate-emr-runtime-clients-all
## List every spark job bypassing the dual-runtime clients (local audit)
validate-emr-runtime-clients-all:
	@echo ""
	@echo "Listing spark jobs that bypass SparkClient/BaseDBUtils/dual-catalog registration"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_emr_runtime_clients.py -a

.PHONY: validate-join-shapes
## Fail if a new/changed join has no extractable hash key (BroadcastNestedLoopJoin risk on EMR).
## Local use: `make validate-join-shapes paths=dags/<domain>/<dag>` or `domain=<domain>`.
validate-join-shapes:
	@echo ""
	@echo "Validating join shapes (range / disjunctive joins that plan as BroadcastNestedLoopJoin on EMR)"
	@echo "=========="
	@echo ""
	@if [ -z "$(paths)" ] && [ -z "$(domain)" ]; then \
		git fetch --no-tags origin +refs/heads/master; \
	fi
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_join_shapes.py $(if $(paths),--paths $(paths),$(if $(domain),--domain $(domain),-b "$(CI_COMMIT_BRANCH)"))

.PHONY: validate-join-shapes-all
## Scan all .sql files under dags/ for nested-loop join risks (local audit)
validate-join-shapes-all:
	@echo ""
	@echo "Scanning all SQL files for nested-loop join risks"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/validate_join_shapes.py -a

MAKE_TARGET ?=
MAKE_EXTRA_ARGS ?=
.PHONY: run-domain-validation
## CI entrypoint: runs a validation make target per changed domain in parallel.
## Detects which domains have changes and calls `make <MAKE_TARGET> domain=<d>` for each.
## Usage: make run-domain-validation MAKE_TARGET=validate-dag-declaration-files MAKE_EXTRA_ARGS="level=debug"
run-domain-validation:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/run_validation_by_domain.py \
		--make-target $(MAKE_TARGET) $(if $(MAKE_EXTRA_ARGS),--make-extra-args "$(MAKE_EXTRA_ARGS)",)

###############################################################################
###################### Common commands ########################################
###############################################################################
dag_name ?="*"

.PHONY: generate-query-manifests
## generates .table_manifest files for DAG query folders (avoids recursive glob at parse time)
generate-query-manifests:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/generate_query_manifests.py -d $(dag_name)

.PHONY: generate-metadata-manifests
## generates .metadata_manifest files for DAG metadata folders
generate-metadata-manifests:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/generate_metadata_manifests.py -d $(dag_name)

.PHONY: generate-data-quality-manifests
## generates .data_quality_manifest files for DAG data_quality folders
generate-data-quality-manifests:
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/generate_data_quality_manifests.py -d $(dag_name)

.PHONY: create-dag-files
## creates the DAG Python files from the DAG declaration YAML files, as of `{dag_name}_dag.py`.
## May receive an optional `dag_name={dag_name}` argument to create only the Python DAG file of the provided DAG.
## ALWAYS skips dags/luigijr/ — that sandbox is built/deployed only by `create-luigijr-dag-files`
## (dedicated Astro instance), so the normal forno/prod DAG bag never includes Luigi's DAGs.
## Also regenerates query/metadata/DQ manifests used at parse time.
create-dag-files: generate-query-manifests generate-metadata-manifests generate-data-quality-manifests
	@echo ""
	@echo "Creating the DAGs' Python files (excluding the luigijr sandbox)"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/create_dag_files.py -d $(dag_name) --exclude-dir luigijr

.PHONY: create-astro-dag-files
## Astro "dev" direct-deploy path: regenerate parse-time manifests, domain bundles, and
## platform migration_{twin,emr,compare}_* exec-passthrough bundles. Does NOT emit per-DAG
## stubs. Skips dags/luigijr/. Pass INCLUDE_VALIDATION=1 for prod-only validation bundles.
create-astro-dag-files: generate-query-manifests generate-metadata-manifests generate-data-quality-manifests
	@echo ""
	@echo "Creating Astro domain + migration bundles + manifests (no per-DAG stubs; excluding luigijr)"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/create_dag_files.py \
		--bundle-domains --bundle-migrations --exclude-dir luigijr \
		$(if $(filter 1,$(INCLUDE_VALIDATION)),--include-validation,)

.PHONY: create-s3-dag-files
## Hybrid forno/prod/Dev Beethoven path: domain bundles only (no migration bundles, no
## per-DAG stubs). Full `dags/` tree is mirrored to S3 afterward. Pass INCLUDE_VALIDATION=1
## on master/hotfix to emit separate _validation_bundle_*.py modules (prod only).
create-s3-dag-files: generate-query-manifests generate-metadata-manifests generate-data-quality-manifests
	@echo ""
	@echo "Creating S3 domain bundles + manifests (no per-DAG stubs, no migration bundles; excluding luigijr)"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/create_dag_files.py \
		--bundle-domains --exclude-dir luigijr \
		$(if $(filter 1,$(INCLUDE_VALIDATION)),--include-validation,)

.PHONY: upload-sla-expectations
## Publish SLA YAML expectations JSON to the data-documentation bucket (requires bucket=...).
upload-sla-expectations:
	@test -n "$(bucket)" || (echo "Usage: make upload-sla-expectations bucket=data-documentation.s3.forno.data.quintoandar.com.br" >&2; exit 1)
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/upload_sla_expectations_into_s3.py $(bucket)

.PHONY: create-luigijr-dag-files
## creates the DAG Python files for the luigijr sandbox ONLY (dags/luigijr/). Used by the
## luigijr pipeline that deploys to the dedicated luigijr Astro instance (see release.yml).
create-luigijr-dag-files:
	@echo ""
	@echo "Creating the luigijr sandbox DAGs' Python files (dags/luigijr/ only)"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/ci_cd/airflow_dag_builder/create_dag_files.py --include-dir luigijr



.PHONY: clean
## delete all compiled python files
clean:
	@find ./ -type d -name '.pytest_cache' -exec rm -rf {} +;
	@find ./ -type d -name 'build' -exec rm -rf {} +;
	@find ./ -type d -name 'dist' -exec rm -rf {} +;
	@find ./ -type d -name 'python_logger.egg-info' -exec rm -rf {} +;
	@find ./ -type d -name 'metastore_db' -exec rm -rf {} +;
	@find ./ -type d -name 'htmlcov' -exec rm -rf {} +;
	@find ./ -type f -name '*derby.log' -exec rm -f {} \;
	@find ./ -type f -name '.version' -exec rm -f {} \;
	@find ./ -type f -name '.package_name' -exec rm -f {} \;
	@find ./ -type f -name '*.pyc' -exec rm -f {} \;
	@find ./ -type f -name '*~' -exec rm -f {} \;
	@find ./dags/ -type f -name '*_dag.py' -exec rm -f {} \;
	@find ./dags/ -empty -type d -delete

.PHONY: help
# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')

.DEFAULT_GOAL := help


.PHONY: dependencies-file
## Automatically generate dependencies.yaml file based on the queries and config files
dependencies-file:
	@echo ""
	@echo "Generating dependencies.yaml file"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/dependency_handling/automate_dependencies.py

.PHONY: freeze-dependency-exceptions
## Automatically generate dependency_exceptions/manual_modifications.yaml, based on the dependencies.yaml file
freeze-dependency-exceptions:
	@echo ""
	@echo "Generating dependencies.yaml file"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/dependency_handling/freeze_dependency_exceptions.py


.PHONY: generate-enrich-dag-declaration
## Automatically generates the DAG Declaration yaml file of an existing enrich DAG, by reading the Python file and other configuration files.
generate-enrich-dag-declaration:
	@echo ""
	@echo "Generating Enrich dag declaration based on dag file"
	@echo "=========="
	@echo ""
	@uv run --project packages/bietlejuice-compiler python $(COMPILER_SCRIPTS)/artifact_generation/generate_enrich_template_from_py_file.py -d $(dag_name)
