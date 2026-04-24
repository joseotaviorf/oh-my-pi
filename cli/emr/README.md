# EMR CLI (experimental)

Containerized CLI that handles AWS EMR job submissions, as well as clusters initialization and and termination.

It supports a **transient** flow (**`transient`** → cluster is created and ends when the step finishes) and a **persistent** flow (**`create-cluster`** → **`submit-step`** one or more times → **`terminate`**).

## Settings

**Global settings** come from YAML under **`config/`**, mounted at **`/config/`** in the container.

Use **`EMR_ENVIRONMENT`** to select the configuration file: **`prod`** (default if unset or empty) → **`config/prod.yml`**, or **`forno`** → **`config/forno.yaml`**.

Per-run options are passed on the **command line** (subcommand name, script URI, cluster id, wait flags, tags, instance overrides, etc.).

## Prerequisites

- Docker and Docker Compose.
- AWS cli.
- Weep (see **`make weep-install`** and **`make weep-auth`** helpers).

## Layout

| Path | Purpose |
|------|---------|
| `src/emr/` | CLI app (installable package) |
| `pyproject.toml` | PEP 621 project (dependencies; used by Docker build) |
| `docker-compose.yml` | Mounts `~/.aws`, **`./config` → `/config`** |
| `Makefile` | `build`, `weep-install`, `weep-auth`, `file-upload`, `file-download`, `app-run`, `transient`, `create-cluster`, `submit-step`, `terminate`, `lint` |
| `config/prod.yml` | **Production** settings (default); **`/config/prod.yml`** in Docker. |
| `config/forno.yaml` | **Forno** settings; **`/config/forno.yaml`** in Docker. |
| `samples/job/sample_pi.py` | Minimal PySpark Pi example |
| `samples/init/worker_init_example.sh` | Example **bootstrap** script (upload to S3; use **`--bootstrap-script-uri`**) |
| `scripts/s3-file-upload.sh` | Upload a local file to an S3 prefix from the **host** (see **`make file-upload`**) |
| `scripts/s3-file-download.sh` | Download one S3 object to a local path (see **`make file-download`**) |

## Authentication

Authentication uses the **standard AWS credential chain** from the local machine mounted inside the CLI (**`${HOME}/.aws`** is mounted read-only).

## Code style

```bash
cd cli/emr
make lint
```

## Settings file

All keys in the table below are **mandatory** in each environment file (**`prod.yml`** / **`forno.yaml`**).

| Key | Type | Purpose |
|-----|------|---------|
| `release_label` | string | EMR release (e.g. `emr-7.5.0`). |
| `subnet_id` | string | VPC subnet id. |
| `job_flow_role` | string | EC2 instance profile **role name**. |
| `service_role` | string | EMR service **role ARN or name**. |
| `poll_sec` | number | Poll interval when **`--wait`** is set. |
| `action_on_failure` | string | Action to take on failure. |
| `deploy_mode` | string | Job deploy mode. |
| `region` | string | EMR client region. |
| `log_uri` | string | EMR log prefix (`s3://…/`). |
| `visible_to_all_users` | bool | Whether the run is visible to all users. |
| `master_instance_type` | string | Master **instance type** (overridable with **`--master-instance-type`**). |
| `core_instance_type` | string | Core **instance type** (overridable with **`--core-instance-type`**). |
| `core_instance_count` | int (≥ 1) | Number of core instances (overridable with **`--core-instance-count`**). |
| `idle_timeout_sec` | int (60–604800) | Idle timeout, for **`create-cluster` only**: terminate the persistent cluster after this many seconds **idle** (no running/pending steps). |

## Command-line reference

```bash
docker compose run --rm app <subcommand> [OPTIONS]
```

### Top-level

| Argument | Default | Description |
|----------|---------|-------------|
| `--help`, `-h` | — | Show help and exit. |
| `--version` | — | Print version and exit. |

### `transient` subcommand

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `--s3-uri` | **yes** | — | PySpark script on S3. |
| `--name` | **yes** | — | Job flow **`Name`**. |
| `--step-name` | no | `Spark application` | EMR step name for this job. |
| `--tag` | no | _(none)_ | Repeatable **`Key=Value`** → EMR tags. |
| `--master-instance-type` | no |  **`m5.xlarge`** | Master **InstanceType** for this run. |
| `--core-instance-type` | no |  **`m5.xlarge`** | Core **InstanceType** for this run. |
| `--core-instance-count` | no | 2 | Core instance count for this run (**≥ 1**). |
| `--bootstrap-script-uri` | no | _(none)_ | **Bootstrap** script URI (`s3://…`); EMR runs it on **every instance** (master + core) at cluster start, before the Spark step. |
| `--wait` / `--no-wait` | no | `--no-wait` | Block until the step completes. |

### `create-cluster` subcommand

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `--name` | **yes** | — | Job flow **`Name`**. |
| `--tag` | no | _(none)_ | Repeatable **`Key=Value`** → EMR tags. |
| `--master-instance-type` | no | from YAML | Master **InstanceType**. |
| `--core-instance-type` | no | from YAML | Core **InstanceType**. |
| `--core-instance-count` | no | from YAML | Core instance count (**≥ 1**). |
| `--bootstrap-script-uri` | no | _(none)_ | Optional bootstrap script URI. |

### `terminate` subcommand

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `--cluster-id` | **yes** | — | Cluster / job flow id (**`j-…`**). |

### `submit-step` subcommand

| Option | Required | Default | Description |
|--------|----------|---------|-------------|
| `--cluster-id` | **yes** | — | Target cluster id. |
| `--s3-uri` | **yes** | — | PySpark **`.py`** on S3. |
| `--step-name` | no | `Spark application` | EMR step name. |
| `--wait` / `--no-wait` | no | `--no-wait` | Block until the step completes. |

## Make

Same command line options are supported via **`make`**. 

**Makefile ↔ CLI:** GNU Make cannot use hyphens in variable names, so each **`--long-option`** is spelled as a **`make`** variable with **hyphens replaced by underscores**. 

For a full passthrough, use **`make app-run args='…'`** and keep the real **`--flags`** inside **`args`**.

| Make target | Role |
|-------------|------|
| **`make app-run args='…'`** | Forwards any subcommand and options, identical to **`docker compose run --rm app …`**: e.g. **`args='transient --name … --s3-uri … --wait'`** |
| **`make transient`** | **`name=`**, **`s3_uri=`**; optional **`step_name=`**, **`bootstrap_script_uri=`**, **`wait=1`** |
| **`make create-cluster`** | **`name=`**; optional **`bootstrap_script_uri=`** |
| **`make submit-step`** | **`cluster_id=`**, **`s3_uri=`**; optional **`step_name=`**, **`wait=1`** |
| **`make terminate`** | **`cluster_id=`** |
| **`make file-upload`** | **`local=`** (file), **`s3_prefix=`** (S3 directory; same as the upload script’s two positional args) |
| **`make file-download`** | **`s3_uri=`**, **`dest=`** (local path) |



## Usage

### 1. Setup Environment (optional, defaults to "prod").

```bash
export EMR_ENVIRONMENT="forno"  # prod
```

### 2. Auth, build.

```bash
cd cli/emr
make weep-auth
make build
```

### 3. Upload jobs and bootstrap scripts as needed.

```bash
make file-upload local=./samples/job/sample_pi.py s3_prefix=s3://your-bucket/emr-cli/jobs/
make file-upload local=./samples/init/worker_init_example.sh s3_prefix=s3://your-bucket/emr-cli/bootstrap/
```

### 4. Transient workflow.

```bash
make transient \
  name=my-test-flow \
  step_name=my-test-flow-step \
  s3_uri=s3://your-bucket/emr-cli/jobs/sample_pi.py \
  bootstrap_script_uri=s3://your-bucket/emr-cli/bootstrap/worker_init_example.sh \
  wait=1
```

### 5. Persistent workflow.

```bash
make create-cluster \
  name=my-test-flow \
  bootstrap_script_uri=s3://your-bucket/emr-cli/bootstrap/worker_init_example.sh
```

Wait for cluster to be created.

```bash
make submit-step \
  cluster_id=j-xxx \
  step_name=my-test-flow-step \
  s3_uri=s3://your-bucket/emr-cli/jobs/sample_pi.py \
  wait=1

make terminate cluster_id=j-xxx
```