---
name: emr-run
description: >-
  Spin up (or reuse) an ad-hoc EMR cluster and run SQL queries or PySpark
  code on it, with the correct EC2 instance profile / JobFlowRole per domain
  (emr-prod default, emr-people-prod for dags/people, or any explicit role).
  Wraps migration-emr-cli: create-cluster → stage → submit-step → result JSON
  from S3 → terminate. Use when the user asks to "subir um cluster no EMR",
  "rodar uma query no EMR", "run this SQL on EMR", "submit a Spark job",
  "testar esse código no EMR", or needs lake data via Spark/Glue with a
  domain-scoped role instead of Databricks or Trino.
---

# EMR run — ad-hoc cluster + queries/code

Spin up a persistent ad-hoc EMR cluster (or reuse one you created), run SQL or
PySpark on it with the right **JobFlowRole**, fetch results as JSON, and
terminate. Uses the same skill-local CLI as `/databricks-emr-migration`:
`.cursor/skills/databricks-emr-migration/migration-emr-cli/` — the only EMR CLI
in the repo whose `create-cluster` accepts `--job-flow-role`.

Run shell steps with the **Bash** tool. All commands below assume:

```bash
CLI_DIR=.cursor/skills/databricks-emr-migration/migration-emr-cli
SKILL_DIR="$PWD/.cursor/skills/emr-run"   # absolute — survives cd into $CLI_DIR
export EMR_SETTINGS_FILE="$PWD/$CLI_DIR/config/migration-validate.yml"   # prod
```

Because each Bash tool call is a fresh shell, re-export the variables (or chain
with `&&`) in every call.

## Prerequisites

* **uv** and the AWS CLI.
* Bootstrap the CLI once per machine:

```bash
cd $CLI_DIR && make sync
```

* AWS credentials via **weep**/ConsoleMe (role `sso_DataAndAnalyticsEMRUser_staff`):

```bash
cd $CLI_DIR && make weep-auth   # installs weep if missing; SSO in browser
aws sts get-caller-identity --output table
```

`EMR_ENVIRONMENT` picks the weep account: `prod` (default, `206390561754`) or
`forno` (`713278628093`). Changing it requires re-running `make weep-auth`.

## Roles (JobFlowRole / EC2 instance profile)

The **JobFlowRole** decides what the cluster can read/write (S3 buckets,
secrets). Picking the wrong one yields `AccessDenied` inside the job, not at
cluster creation.

| Scope | JobFlowRole | When |
| ----- | ----------- | ---- |
| Default | `emr-prod` | Most domains / general lake reads |
| People | `emr-people-prod` | Anything touching `dags/people` data (HR buckets, people secrets) |
| Other | pass explicitly | Any other instance profile the user names |

Ask the user which role fits when the data domain is ambiguous. A cluster's
role is fixed at creation — to switch roles, create another cluster.

## 1. Reuse or create the cluster

Reuse only clusters **this skill created** (tag `Purpose=emr-run`) whose
`JobFlowRole` tag matches the role you need. Never submit ad-hoc steps to
fleet DAG clusters or `migration-validation` clusters.

```bash
cd $CLI_DIR && uv run migration-emr-cli list-clusters --tag Purpose=emr-run --output json
```

If a matching cluster is `WAITING`/`RUNNING`, use its `j-…` id. Otherwise create:

```bash
ROLE=emr-people-prod   # or emr-prod, etc.
cd $CLI_DIR && uv run migration-emr-cli create-cluster \
  --name "emr-run-${ROLE}-$(date +%s)" \
  --job-flow-role "$ROLE" \
  --no-use-spot \
  --tag Purpose=emr-run \
  --tag "JobFlowRole=${ROLE}" \
  --tag "Owner=$(whoami)"
```

Then poll until `WAITING` (~8–12 min; check every ~60 s):

```bash
cd $CLI_DIR && uv run migration-emr-cli describe-cluster --cluster-id j-XXXX --output json
```

Sizing defaults come from `config/migration-validate.yml` (m7g.2xlarge master +
3 cores, Glue metastore, Delta, `idle_timeout_sec: 7200` → auto-terminates
after 2 h idle). Each m7g.2xlarge core node fits ~2 executors (`spark-defaults`:
8g+2g executors, 2 cores each, dynamic allocation 1–12), so core count ≈
parallelism. Pick by workload, not trial and error:

* **`--core-instance-count 1`** (~2 executors) — the default for ad-hoc
  validation: `DESCRIBE`/`SHOW`, partition-bounded reads (one load window, one
  day, one entity), single-table `SELECT`s, small-file/JSON inspection.
* **Keep the default 3 cores** (~6 executors) — full scans of large partitioned
  tables (months of history, tens of GB+), joins across two or more large
  tables, or population-wide aggregations.

Under-sizing costs time, never correctness: with dynamic allocation the step
still completes, just slower — if it drags past ~15–20 min on 1 core,
terminate and recreate with 3. What you must NOT shrink is the **instance
type**: the `spark-defaults` sizes assume m7g.2xlarge nodes, and on smaller
cores (e.g. m7g.xlarge) the executor container never fits next to the AM, so
every step hangs forever at `Initial job has not accepted any resources` —
spark-defaults are fixed at cluster creation and `submit-step` cannot
override them.

## 2. Run a SQL query

Write the SQL to a local file (multiple statements separated by `;` are run in
order; the **last** statement's result is returned). Then stage + submit using
the generic runner [`run_sql_job.py`](run_sql_job.py):

```bash
RUN_ID=$(date +%s)
cd $CLI_DIR && uv run migration-emr-cli stage --key "emr-run/$RUN_ID/query.sql" --file /path/to/query.sql
```

`stage` prints the uploaded `s3://…/emr-run/<run_id>/query.sql` URI — capture
it as `SQL_URI` and derive `RESULT_URI="${SQL_URI%query.sql}result.json"`
(never hardcode the bucket; it differs between prod and forno). Then:

```bash
cd $CLI_DIR && uv run migration-emr-cli submit-step \
  --cluster-id j-XXXX \
  --step-name "emr-run-sql-$RUN_ID" \
  --uri "$SKILL_DIR/run_sql_job.py" \
  --job-args "--sql-s3-uri $SQL_URI --result-s3-uri $RESULT_URI --limit 1000" \
  --wait --follow-logs --wait-result --result-s3-uri "$RESULT_URI"
```

Notes:

* A bare local `--uri` path is auto-uploaded to `staging_uri` — pass the
  **absolute** path to `run_sql_job.py` (relative paths resolve from the CLI cwd).
* `--wait-result` prints `RESULT_JSON={…}` on stdout: `schema`, `rows` (up to
  `--limit`), `row_count`, `truncated`, `duration_sec`, and `error` on failure.
  For large results, download `$RESULT_URI` with `aws s3 cp` and
  inspect with **Read**/**Grep** instead of dumping it all to the terminal.
* Long queries: drop `--follow-logs` to reduce noise; keep `--wait`.

## 3. Run PySpark code

Any self-contained PySpark driver works the same way — build the session like
`run_sql_job.py` does (Glue + Delta + `enableHiveSupport`) so lake tables
resolve:

```bash
cd $CLI_DIR && uv run migration-emr-cli submit-step \
  --cluster-id j-XXXX \
  --step-name my-adhoc-job \
  --uri /absolute/path/to/my_job.py \
  --job-args '--my-flag value' \
  --wait --follow-logs
```

`--job-args` become the driver's `sys.argv` (not `spark-submit --conf`). The
CLI already injects Delta/Glue/`SPARK_RUNTIME=emr` confs before the script.
`--uri` must point to a **`.py`** file — JARs are not supported by this CLI.
Don't set `spark.databricks.*` confs: EMR silently drops them by design.

If the code imports **bietlejuice** (e.g. `DeltaLoader`), the cluster needs the
wheels bootstrap at creation time:

```bash
  --bootstrap-script-uri "$PWD/../../../../packages/emr-cli/samples/init/emr_init_minimal.sh" \
  --bootstrap-arg 's3://artifacts.s3.data.quintoandar.com.br'   # prod
```

On forno the artifacts bucket is `s3://artifacts.s3.forno.data.quintoandar.com.br`.

## 4. One-shot alternative (transient)

For a single job with no reuse, `transient` creates the cluster, runs the step,
and terminates it (accepts the same `--uri`/`--job-args`; role comes from the
settings file — `transient` has **no** `--job-flow-role` flag, so for
`emr-people-prod` use the persistent flow above).

## 5. Terminate

When the user is done (don't rely only on the 2 h idle timeout):

```bash
cd $CLI_DIR && uv run migration-emr-cli terminate --cluster-id j-XXXX
```

## Debugging failures

Step failed / no output: use the **`emr-dump-logs`** skill
(`.cursor/skills/emr-dump-logs/SKILL.md`). Ad-hoc CLI steps log under
`cli/<cluster_id>/steps/<step_id>/` in the artifacts bucket.

Other diagnostics:

* **Step submitted but never appears on the cluster** — IAM scoping: EMR EC2
  actions require the tag `for-use-with-amazon-emr-managed-policies=true`.
  The CLI auto-adds it; only hand-rolled `aws emr` calls hit this.
* **Stage/executor analysis** (skew, shuffle, slow stages): point the user to
  the Spark UI — live via AWS Console → EMR → \<cluster\> → *Application user
  interfaces* (needs SSO/VPN), or *Persistent application UIs* → Spark History
  Server for up to ~30 days after the cluster terminates.

## Forno

Point the settings at the **CLI's own** forno file and re-auth:

```bash
export EMR_ENVIRONMENT=forno
export EMR_SETTINGS_FILE="$PWD/$CLI_DIR/config/forno.yaml"
cd $CLI_DIR && make weep-auth
```

Same commands afterwards — buckets, subnet, and default role (`emr-forno`)
switch to the forno account. Do **not** point `EMR_SETTINGS_FILE` at
`packages/emr-cli/config/forno.yaml`: that file has keys (`os_release_label`)
that `migration-emr-cli`'s stricter loader rejects.

## Hard rules

* **Never** submit steps to fleet/DAG clusters or clusters you didn't create
  via this skill (`Purpose=emr-run` tag) — other clusters belong to Airflow or
  the migration skill.
* Read-only by default: run `SELECT`s. Only run DDL/DML that writes to lake
  tables when the user explicitly asks, and never against `dw_*`/production
  tables owned by DAGs.
* Never print or commit exported `AWS_*` credentials.
* Terminate (or confirm idle timeout) at the end of the session — clusters
  cost money.
* Environment values (buckets, roles, subnets) come from the config YAMLs —
  never hardcode new ones in code.
