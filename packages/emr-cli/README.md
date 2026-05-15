# EMR CLI (experimental)

Containerized CLI that handles AWS EMR job submissions, as well as clusters initialization and and termination.

It supports a **transient** flow (**`transient`** → cluster is created and ends when the step finishes), a **persistent** flow (**`create-cluster`** → **`submit-step`** one or more times → **`terminate`**), and **`dump-logs`** to print objects already stored under the configured S3 log prefix.

## Settings

**Global settings** come from YAML under **`config/`**, mounted at **`/config/`** in the container.

Use **`EMR_ENVIRONMENT`** to select the configuration file: **`prod`** (default if unset or empty) → **`config/prod.yml`**, or **`forno`** → **`config/forno.yaml`**.

Per-run options are passed on the **command line** (subcommand name, script URI, cluster id, wait flags, tags, instance overrides, etc.).

## Prerequisites

- Docker and Docker Compose.
- AWS cli.
- Weep (see **`make weep-install`** and **`make weep-auth`** helpers).

## Layout

| Path                                  | Purpose                                                                                                                                                                                                                                           |
| ------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `src/emr/`                            | CLI app (installable package)                                                                                                                                                                                                                     |
| `pyproject.toml`                      | PEP 621 project (dependencies; used by Docker build)                                                                                                                                                                                              |
| `docker-compose.yml`                  | Mounts `~/.aws`, **`./config` → `/config`**, **`./samples` → `/app/samples`** (matches **`WORKDIR /app`**)                                                                                                                                        |
| `Makefile`                            | `build`, `weep-install`, `weep-auth`, `file-upload`, `file-download`, `app-run`, `transient`, `create-cluster`, `submit-step`, `terminate`, `dump-logs`, `lint`                                                                                |
| `config/prod.yml`                     | **Production** settings (default); **`/config/prod.yml`** in Docker.                                                                                                                                                                              |
| `config/forno.yaml`                   | **Forno** settings; **`/config/forno.yaml`** in Docker.                                                                                                                                                                                           |
| `samples/job/sample_pi.py`            | Minimal PySpark Pi example                                                                                                                                                                                                                        |
| `samples/job/sample_delta_loader.py`  | Uses the **bi-etl-ejuice** package on the cluster: **`DeltaLoader`**, **`create_emr_spark_session`**, **`QuintoAndarLogger`**; registers **`--target-table`** via **`saveAsTable`** (see [Samples and bi-etl-ejuice](#samples-and-bi-etl-ejuice)) |
| `samples/init/worker_init_example.sh` | Example **bootstrap** script (upload to S3; use **`--bootstrap-script-uri`**)                                                                                                                                                                     |
| `samples/init/emr_init_minimal.sh`    | Minimal bootstrap: install **bi-etl-ejuice** + **python-logger** wheels and validate imports (pass **`--bootstrap-arg`** with artifacts bucket URI)                                                                                               |
| `scripts/s3-file-upload.sh`           | Upload a local file to an S3 prefix from the **host** (see **`make file-upload`**)                                                                                                                                                                |
| `scripts/s3-file-download.sh`         | Download one S3 object to a local path (see **`make file-download`**)                                                                                                                                                                             |

**Docker `app` container:** **`WORKDIR`** is **`/app`**. Host **`cli/emr/samples`** is mounted at **`/app/samples`**.

### Samples and bi-etl-ejuice

| Sample                                   | Depends on **bi-etl-ejuice**? | Notes                                                                                                                                                                                                |
| ---------------------------------------- | ----------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`samples/job/sample_pi.py`**           | No                            | Plain **`pyspark`** only; runs without installing the monorepo wheel.                                                                                                                                |
| **`samples/job/sample_delta_loader.py`** | **Yes**                       | Imports **`bietlejuice...spark_session_factory`**, **`bietlejuice...DeltaLoader`**, and **`quintoandar_logger`**. The EMR cluster must have those packages on **`PYTHONPATH`** before the step runs. |

For **`sample_delta_loader.py`**, use a **bootstrap** that downloads and **`pip install`s** the wheels from your **artifacts** bucket (same layout as production: **`…/bi-etl-ejuice/bi_etl_ejuice-…whl`**, **`…/python-logger/…quintoandar_logger…whl`**). This repo ships **[`samples/init/emr_init_minimal.sh`](samples/init/emr_init_minimal.sh)** for a small POC; production uses **[`scripts/emr_init_script.sh`](../../../scripts/emr_init_script.sh)**. 

## Authentication

Authentication uses the **standard AWS credential chain** from the local machine mounted inside the CLI (**`${HOME}/.aws`** is mounted read-only).

## Code style

```bash
cd packages/emr-cli
make lint
```

## Settings file

The settings file contains "global" settings that should be fined for most runs. Do not edit this file directly, instead do override options using command line arguments.

**Required** keys in each environment file (**`prod.yml`** / **`forno.yaml`**):

| Key                    | Type            | Purpose                                                                                                                                                                                                                                                        |
| ---------------------- | --------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `release_label`        | string          | EMR release (e.g. `emr-7.5.0`).                                                                                                                                                                                                                                |
| `subnet_id`            | string          | VPC subnet id.                                                                                                                                                                                                                                                 |
| `job_flow_role`        | string          | EC2 instance profile **role name**.                                                                                                                                                                                                                            |
| `service_role`         | string          | EMR service **role ARN or name**.                                                                                                                                                                                                                              |
| `poll_sec`             | number          | Poll interval when **`--wait`** is set.                                                                                                                                                                                                                        |
| `action_on_failure`    | string          | Action to take on failure.                                                                                                                                                                                                                                     |
| `deploy_mode`          | string          | Job deploy mode.                                                                                                                                                                                                                                               |
| `region`               | string          | EMR client region.                                                                                                                                                                                                                                             |
| `log_uri`              | string          | EMR log prefix (`s3://…/`) passed to **`RunJobFlow`**.                                                                                                                                                                                                         |
| `dump_logs_base_uri`   | string          | S3 prefix (`s3://…/`) for **`dump-logs`** only; join with the relative path argument. Must not be empty after the bucket. Not overridable from the CLI.                                                                           |
| `staging_uri`          | string          | S3 prefix (`s3://…/`) for uploading local **`--uri`** / **`--bootstrap-script-uri`** paths.                                                                                                                                                                    |
| `visible_to_all_users` | bool            | Whether the run is visible to all users.                                                                                                                                                                                                                       |
| `master_instance_type` | string          | Master **instance type** (overridable with **`--master-instance-type`**).                                                                                                                                                                                      |
| `core_instance_type`   | string          | Core **instance type** (overridable with **`--core-instance-type`**).                                                                                                                                                                                          |
| `core_instance_count`  | int (≥ 1)       | Number of core instances (overridable with **`--core-instance-count`**).                                                                                                                                                                                       |
| `idle_timeout_sec`     | int (60–604800) | Idle timeout, for **`create-cluster` only**: terminate the persistent cluster after this many seconds **idle** (no running/pending steps).                                                                                                                     |
| `use_spot`             | bool            | SPOT vs ON_DEMAND for core nodes (default overridable per run).                                                                                                                                                                                                |
| `applications`         | list            | EMR **Applications** (e.g. Hadoop, Hive, Livy, Spark) — aligned with **`emr_cluster_base`** / **`emr_applications`** in **[`bietlejuice/forno_conf.yml`](../../../bietlejuice/forno_conf.yml)**.                                                               |
| `configurations`       | list            | EMR **Configurations** (Iceberg/Delta defaults, **`spark-hive-site`** Glue client, …). Can be **`[]`**. Full Airflow clusters also use **`yarn-env`** + **[`scripts/emr_init_script.sh`](../../../scripts/emr_init_script.sh)** (wheels, JARs, UC); see below. |


## Command-line reference

```bash
docker compose run --rm app <subcommand> [OPTIONS]
```




### Top-level

| Argument       | Default | Description             |
| -------------- | ------- | ----------------------- |
| `--help`, `-h` | —       | Show help and exit.     |
| `--version`    | —       | Print version and exit. |

### `transient` subcommand

| Option                               | Required | Default             | Description                                                                                                                                                                                              |
| ------------------------------------ | -------- | ------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `--uri`                              | **yes**  | —                   | PySpark script: **`s3://…`** or a **bare filesystem path** (must exist). Relative paths resolve from **cwd** — in Docker **`samples/job/...`** with **`WORKDIR /app`** (see Layout).                     |
| `--name`                             | **yes**  | —                   | Job flow **`Name`**.                                                                                                                                                                                     |
| `--step-name`                        | no       | `Spark application` | EMR step name for this job.                                                                                                                                                                              |
| `--tag`                              | no       | _(none)_            | Repeatable **`Key=Value`** → EMR tags.                                                                                                                                                                   |
| `--master-instance-type`             | no       | **`m5.xlarge`**     | Master **InstanceType** for this run.                                                                                                                                                                    |
| `--core-instance-type`               | no       | **`m5.xlarge`**     | Core **InstanceType** for this run.                                                                                                                                                                      |
| `--core-instance-count`              | no       | 2                   | Core instance count for this run (**≥ 1**).                                                                                                                                                              |
| `--bootstrap-script-uri`             | no       | _(none)_            | Same as **`--uri`**: **`s3://…`** or bare path (relative → cwd).                                                                                                                                         |
| `--bootstrap-arg`                    | no       | _(none)_            | Repeatable; forwarded as **`ScriptBootstrapAction.Args`** after **`Path`** (e.g. artifacts bucket **`s3://…`**).                                                                                         |
| `--job-args`                         | no       | _(none)_            | Shell-style string (**`shlex`**) of **Python driver** arguments after the **`.py`** URI (**`sys.argv`**); not **`spark-submit`** flags such as **`--conf`**. Preferred for **`make`** (**`JOB_ARGS=`**). |
| `--job-arg`                          | no       | _(none)_            | Repeatable driver argument after the **`.py`** URI; after **`--job-args`** when both set. Not for **`spark-submit`** options before the script.                                                          |
| `--use-spot` / `--no-use-spot`       | no       | from YAML           | Override **`use_spot`**.                                                                                                                                                                                 |
| `--wait` / `--no-wait`               | no       | `--no-wait`         | Block until the step completes.                                                                                                                                                                          |
| `--follow-logs` / `--no-follow-logs` | no       | `--no-follow-logs`  | With **`--wait`**: poll EMR step logs on S3 (**`stdout`** / **`stderr`**) and print new bytes until the step finishes.                                                                                   |

### `create-cluster` subcommand

| Option                         | Required | Default   | Description                                                |
| ------------------------------ | -------- | --------- | ---------------------------------------------------------- |
| `--name`                       | **yes**  | —         | Job flow **`Name`**.                                       |
| `--tag`                        | no       | _(none)_  | Repeatable **`Key=Value`** → EMR tags.                     |
| `--master-instance-type`       | no       | from YAML | Master **InstanceType**.                                   |
| `--core-instance-type`         | no       | from YAML | Core **InstanceType**.                                     |
| `--core-instance-count`        | no       | from YAML | Core instance count (**≥ 1**).                             |
| `--bootstrap-script-uri`       | no       | _(none)_  | Optional bootstrap script.                                 |
| `--bootstrap-arg`              | no       | _(none)_  | Repeatable bootstrap **`Args`** (same as **`transient`**). |
| `--use-spot` / `--no-use-spot` | no       | from YAML | Override **`use_spot`**.                                   |

### `submit-step` subcommand

| Option                               | Required | Default             | Description                            |
| ------------------------------------ | -------- | ------------------- | -------------------------------------- |
| `--cluster-id`                       | **yes**  | —                   | Target cluster id.                     |
| `--uri`                              | **yes**  | —                   | Same as **`transient --uri`**.         |
| `--step-name`                        | no       | `Spark application` | EMR step name.                         |
| `--wait` / `--no-wait`               | no       | `--no-wait`         | Block until the step completes.        |
| `--follow-logs` / `--no-follow-logs` | no       | `--no-follow-logs`  | Same as **`transient --follow-logs`**. |
| `--job-args`                         | no       | _(none)_            | Same as **`transient --job-args`**.    |
| `--job-arg`                          | no       | _(none)_            | Same as **`transient --job-arg`**.     |

### `terminate` subcommand

| Option         | Required | Default | Description                        |
| -------------- | -------- | ------- | ---------------------------------- |
| `--cluster-id` | **yes**  | —       | Cluster / job flow id (**`j-…`**). |

### `dump-logs` subcommand

| Argument            | Required | Description                                                                                                                                                                                          |
| ------------------- | -------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`RELATIVE_PATH`** | **yes**  | S3 key suffix after **`dump_logs_base_uri`** (from the env YAML), e.g. **`cli/j-1AB2C3D4E5F6/steps/s-ABCDEF123456/`** to print every object under that prefix, or a single object path ending in **`stderr.gz`**. |
 

## Make

Same command line options are supported via **`make`**.

**Makefile ↔ CLI:** GNU Make cannot use hyphens in variable names, so each **`--long-option`** is spelled as a **`make`** variable with **hyphens replaced by underscores**.

For a full passthrough, use **`make app-run args='…'`** and keep the real **`--flags`** inside **`args`**.

| Make target                 | Role                                                                                                                                                                                                                       |
| --------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **`make app-run args='…'`** | Forwards any subcommand and options, identical to **`docker compose run --rm app …`**: e.g. **`args='transient --name … --uri … --wait'`**                                                                                 |
| **`make transient`**        | **`name=`**, **`uri=`**; optional **`step_name=`**, **`bootstrap_script_uri=`**, **`bootstrap_arg=`**, **`JOB_ARGS=`** (maps to **`--job-args`**), **`wait=1`**, **`follow_logs=1`**, **`use_spot=1`** or **`use_spot=0`** |
| **`make create-cluster`**   | **`name=`**; optional **`bootstrap_script_uri=`**, **`bootstrap_arg=`**, **`use_spot=1`** or **`use_spot=0`**                                                                                                              |
| **`make submit-step`**      | **`cluster_id=`**, **`uri=`**; optional **`step_name=`**, **`JOB_ARGS=`**, **`wait=1`**, **`follow_logs=1`**                                                                                                               |
| **`make terminate`**        | **`cluster_id=`**                                                                                                                                                                                                          |
| **`make dump-logs`**        | **`path=`** — S3 suffix after **`dump_logs_base_uri`** (same as **`dump-logs RELATIVE_PATH`**)                                                                                                                                  |
| **`make file-upload`**      | **`local=`** (file), **`s3_prefix=`** (S3 directory; same as the upload script’s two positional args)                                                                                                                      |
| **`make file-download`**    | **`s3_uri=`**, **`dest=`** (local path)                                                                                                                                                                                    |



## Usage

### 1. Setup Environment (optional, defaults to "prod").

```bash
export EMR_ENVIRONMENT="forno"  # prod
```

### 2. Auth, build.

```bash
cd packages/emr-cli
make weep-auth
make build
```


### 3. Transient workflow.

```bash
make transient \
  name=my-test-flow \
  step_name=my-test-flow-step \
  uri=samples/job/sample_pi.py \
  bootstrap_script_uri=samples/init/worker_init_example.sh \
  wait=1 \
  follow_logs=1
```



### 4. Persistent workflow.

```bash
make create-cluster \
  use_spot=0 \
  name=my-test-flow \
  bootstrap_script_uri=samples/init/worker_init_example.sh
```

Wait for cluster to be created.

```bash
make submit-step \
  cluster_id=j-xxx \
  step_name=my-test-flow-step \
  uri=samples/job/sample_pi.py \
  wait=1 \
  follow_logs=1

make terminate cluster_id=j-xxx
```

### 5. Dump logs from a folder.


```bash
make dump-logs path=cli/j-16G15MMFKF7B4/steps/s-08173765NJH35345HN8/

make dump-logs path=dags/bietlejuice.enrich_airflow/j-U1T1K7WLM08Z/steps/s-00722212VHMT0ZDYH6IQ/

make dump-logs path=dags/bietlejuice.enrich_airflow/j-U1T1K7WLM08Z/steps/s-00722212VHMT0ZDYH6IQ/stderr.gz
```


# Airflow EMR vs this CLI

DAG-defined clusters in **`forno_conf.yml`** (**`emr_cluster_base`**) install **Hadoop, Hive, JupyterEnterpriseGateway, Livy, Spark**, bootstrap **`bi-etl-ejuice/emr_init_script.sh`**, and pass Spark/Databricks env via **`yarn-env`**. This CLI YAML mirrors **applications** and a **subset** of **configurations** so **`RunJobFlow`** matches production EMR software; **complete** bi-etl-ejuice parity (inmetro, JDBC jars, Deequ, UC sync) still requires the **full** init script from artifacts and the Airflow **`yarn-env`** block where applicable.

For a light POC, **`samples/init/emr_init_minimal.sh`** installs only wheels needed for **`DeltaLoader`** / **`create_emr_spark_session`**.

Details on **default Spark `--conf`** vs **`--job-args`** are in **Important nuances** under [Command-line reference](#command-line-reference).

## Important nuances: default `--conf` vs `--job-args`

**Default `--conf` (built into every CLI Spark step):** **`build_spark_step`** (`steps.py`) always inserts **`--conf`** tokens **before** the **`.py`** URI on **`transient`** and **`submit-step`**. They align with **`create_emr_spark_session`** and **`RuntimeDetector`** on YARN:

- **`spark.sql.extensions`** → **`io.delta.sql.DeltaSparkSessionExtension`**
- **`spark.sql.catalog.spark_catalog`** → **`org.apache.spark.sql.delta.catalog.DeltaCatalog`**
- **`spark.hadoop.fs.s3a.acl.default`** / **`spark.hadoop.fs.s3a.canned.acl`** → **`BucketOwnerFullControl`**
- **`spark.yarn.appMasterEnv.SPARK_RUNTIME`** / **`spark.driverEnv.SPARK_RUNTIME`** → **`emr`**

Those defaults are **not** driven by **`--job-args`**. Extra Spark options such as another **`--conf`** would need to appear **before** the script URI in **`spark-submit`**; the CLI does not yet expose a flag for that.

**`--job-args` / `--job-arg`:** Tokens **after** the **`.py`** URI are **spark-submit application arguments** — they become the Python driver’s **`sys.argv`**. Use them for script flags (e.g. **`sample_delta_loader.py`** **`--target-table`**, **`--target-path`**). They are **not** where you pass **`spark-submit`** options like **`--conf`** or **`--packages`**.

## Equivalent `spark-submit` on the cluster

EMR runs **`command-runner.jar`** with arguments equivalent to the following (binary **`/usr/lib/spark/bin/spark-submit`** — the path EMR documents for interactive submit). **`deploy_mode`** matches **`deploy_mode`** in **`config/*.yml`** (often **`cluster`**). Tokens **after** the **`.py`** URI are **Python `sys.argv`** from **`--job-args`** / **`--job-arg`**, not extra **`--conf`**.

```bash
/usr/lib/spark/bin/spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --conf spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension \
  --conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog \
  --conf spark.hadoop.fs.s3a.acl.default=BucketOwnerFullControl \
  --conf spark.hadoop.fs.s3a.canned.acl=BucketOwnerFullControl \
  --conf spark.yarn.appMasterEnv.SPARK_RUNTIME=emr \
  --conf spark.driverEnv.SPARK_RUNTIME=emr \
  s3://your-bucket/path/to/driver.py \
  --your-script-arg value
```

## Bootstrap and PySpark arguments

Production EMR clusters pass [**`scripts/emr_init_script.sh`**](../../../scripts/emr_init_script.sh) a single argument: the **artifacts bucket** base URI. The CLI mirrors that with **`--bootstrap-arg`**.

Minimal POC bootstrap [**`samples/init/emr_init_minimal.sh`**](samples/init/emr_init_minimal.sh) uses the same contract.

For PySpark script arguments (everything **`spark-submit`** passes after the **`.py`** URI), prefer **`--job-args`** with a **single quoted string** (parsed like a shell line). You can still use repeatable **`--job-arg`**; tokens from **`--job-args`** come first, then **`--job-arg`** values.

Examples below use **Forno** (**`export EMR_ENVIRONMENT=forno`** → **`config/forno.yaml`**). **`bootstrap-arg`** is the artifacts **bucket base** where **`emr_init_minimal.sh`** pulls wheels (`…/bi-etl-ejuice/…`, `…/python-logger/…`). **`--target-path`** is the Delta prefix; **`--target-table`** is registered in Glue/Hive via **`DeltaLoader.saveAsTable`**.

### Full command line: `sample_delta_loader.py` via EMR CLI (Docker)

Run from **`cli/emr`** (so Compose and **`./samples`** resolve). Authenticate AWS first (**`make weep-auth`** if you use Weep).

```bash
cd packages/emr-cli
export EMR_ENVIRONMENT=forno
docker compose run --rm app transient \
  --name emr-delta-sample \
  --uri samples/job/sample_delta_loader.py \
  --bootstrap-script-uri samples/init/emr_init_minimal.sh \
  --bootstrap-arg 's3://artifacts.s3.forno.data.quintoandar.com.br' \
  --job-args '--target-table emr_cli_samples.emr_delta_sample --target-path s3://artifacts.s3.forno.data.quintoandar.com.br/emr/cli/samples/emr_delta_sample/' \
  --wait
```

#### Same flow with **Make**

```bash
cd packages/emr-cli
export EMR_ENVIRONMENT=forno
make transient \
  name=emr-delta-sample \
  uri=samples/job/sample_delta_loader.py \
  bootstrap_script_uri=samples/init/emr_init_minimal.sh \
  bootstrap_arg='s3://artifacts.s3.forno.data.quintoandar.com.br' \
  JOB_ARGS='--target-table emr_cli_samples.emr_delta_sample --target-path s3://artifacts.s3.forno.data.quintoandar.com.br/emr/cli/samples/emr_delta_sample/' \
  wait=1
```

### Full command line: run **`sample_delta_loader.py` manually on the EMR master

Node must already have **bi-etl-ejuice** installed (bootstrap). Upload **`samples/job/sample_delta_loader.py`** to S3 (**`make file-upload`** into **`staging_uri`**, or your own key). Set **`S3_URI_TO_SCRIPT`** to that **`s3://`** object.

```bash
/usr/lib/spark/bin/spark-submit \
  --master yarn \
  --deploy-mode cluster \
  --conf spark.sql.extensions=io.delta.sql.DeltaSparkSessionExtension \
  --conf spark.sql.catalog.spark_catalog=org.apache.spark.sql.delta.catalog.DeltaCatalog \
  --conf spark.hadoop.fs.s3a.acl.default=BucketOwnerFullControl \
  --conf spark.hadoop.fs.s3a.canned.acl=BucketOwnerFullControl \
  --conf spark.yarn.appMasterEnv.SPARK_RUNTIME=emr \
  --conf spark.driverEnv.SPARK_RUNTIME=emr \
  "${S3_URI_TO_SCRIPT}" \
  --target-table emr_cli_samples.emr_delta_sample \
  --target-path 's3://artifacts.s3.forno.data.quintoandar.com.br/emr/cli/samples/emr_delta_sample/'
```

Use another bucket/prefix if your role cannot write to Forno artifacts; production uses different URIs.
