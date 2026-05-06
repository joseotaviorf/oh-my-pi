COMPOSE ?= docker compose

.PHONY: build shell run weep-auth weep-install lint check-style file-upload file-download \
	app-run transient create-cluster submit-step terminate

build:
	$(COMPOSE) build app

# Authenticate with weep/consoleme and refresh credentials
weep-auth:
	./scripts/weep-auth.sh

# Install weep (idempotent)
weep-install:
	./scripts/install-weep.sh

lint:
	@python -m black src/emr/

check-style:
	@python -m black --check src/emr/ && echo "\n\nSuccess\n" || (echo "\n\nFailure\n\nRun \"make lint\" in cli/emr to fix\n" && exit 1)

# Makefile vars mirror CLI flags: replace "--foo-bar" with "foo_bar" (see README).
# Upload: local file + S3 prefix (same as s3-file-upload.sh positional args).
# Usage: make file-upload local=path/to/file s3_prefix=s3://bucket/prefix/
file-upload:
	@test -n "$(local)" && test -n "$(s3_prefix)" || (echo 'Usage: make file-upload local=path/to/file s3_prefix=s3://bucket/prefix/' >&2; exit 1)
	./scripts/s3-file-upload.sh "$(local)" "$(s3_prefix)"

# Download: full object URI + local path.
# Usage: make file-download s3_uri=s3://bucket/key dest=./local-file
file-download:
	@test -n "$(s3_uri)" && test -n "$(dest)" || (echo 'Usage: make file-download s3_uri=s3://bucket/key dest=./local-file' >&2; exit 1)
	./scripts/s3-file-download.sh "$(s3_uri)" "$(dest)"

# Same as: docker compose run --rm app <subcommand> [OPTIONS]
# Usage: make app-run args='transient --name my-flow --uri s3://bucket/j.py --wait'
app-run:
	@test -n "$(args)" || (echo 'Usage: make app-run args="transient|create-cluster|submit-step|terminate ..."' >&2; exit 1)
	$(COMPOSE) run --rm app $(args)

# Transient cluster + step (README §3). Optional: step_name, bootstrap_script_uri, wait=1, use_spot=1|0
transient:
	@test -n "$(name)" && test -n "$(uri)" || (echo 'Usage: make transient name=... uri=... [step_name=...] [bootstrap_script_uri=...] [wait=1] [use_spot=1|0]' >&2; exit 1)
	$(COMPOSE) run --rm app transient \
		--name "$(name)" \
		$(if $(strip $(step_name)),--step-name "$(step_name)") \
		--uri "$(uri)" \
		$(if $(strip $(bootstrap_script_uri)),--bootstrap-script-uri "$(bootstrap_script_uri)") \
		$(if $(filter 1 true yes,$(use_spot)),--use-spot,$(if $(filter 0 false no,$(use_spot)),--no-use-spot,)) \
		$(if $(filter 1 true yes,$(wait)),--wait)

# Persistent cluster (README §4). Optional: bootstrap_script_uri, use_spot=1|0
create-cluster:
	@test -n "$(name)" || (echo 'Usage: make create-cluster name=... [bootstrap_script_uri=...] [use_spot=1|0]' >&2; exit 1)
	$(COMPOSE) run --rm app create-cluster \
		--name "$(name)" \
		$(if $(strip $(bootstrap_script_uri)),--bootstrap-script-uri "$(bootstrap_script_uri)") \
		$(if $(filter 1 true yes,$(use_spot)),--use-spot,$(if $(filter 0 false no,$(use_spot)),--no-use-spot,))

# Add Spark step to a running cluster (README §4). Optional: step_name, wait=1
submit-step:
	@test -n "$(cluster_id)" && test -n "$(uri)" || (echo 'Usage: make submit-step cluster_id=... uri=... [step_name=...] [wait=1]' >&2; exit 1)
	$(COMPOSE) run --rm app submit-step \
		--cluster-id "$(cluster_id)" \
		$(if $(strip $(step_name)),--step-name "$(step_name)") \
		--uri "$(uri)" \
		$(if $(filter 1 true yes,$(wait)),--wait)

# Terminate cluster (README §4)
terminate:
	@test -n "$(cluster_id)" || (echo 'Usage: make terminate cluster_id=...' >&2; exit 1)
	$(COMPOSE) run --rm app terminate \
		--cluster-id "$(cluster_id)"
