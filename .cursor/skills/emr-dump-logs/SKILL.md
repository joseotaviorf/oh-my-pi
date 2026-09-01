---
name: emr-dump-logs
description: >-
  Fetch and diagnose Amazon EMR Spark step failures from S3 logs (Airflow
  "Unknown Error", cluster j-…, step s-…, YARN application_…). Use when
  debugging EMR DAG failures, reading step stderr/stdout, or inspecting
  container logs under artifacts.s3.data.quintoandar.com.br/emr/logs/.
  Triggers: "why did this EMR step fail", "dump the EMR logs", "read the step
  stderr", "diagnose this Airflow EMR failure", or a pasted S3 log prefix +
  j-/s- ids.
---

# EMR dump logs

Read-only workflow to pull EMR step / YARN container logs from S3 using
ConsoleMe credentials via **`qli aws`**. Prefer this over the AWS Console when
debugging an EMR DAG failure from Claude Code.

Run the shell steps with the **Bash** tool; inspect the extracted plaintext
with the **Read** / **Grep** tools (they are faster and cheaper than dumping
whole files through `cat`).

## Prerequisites

* [qli](https://github.com/quintoandar/qli) installed and ConsoleMe challenge
  configured (`~/.qli/aws/config.yaml`).
* IdN / ConsoleMe role **`sso_DataAndAnalyticsEMRUser_staff`** (guide:
  EMR Developer Guide § Prerequisites + §4 Accessing logs). No access yet?
  Request in IdN: **Central de Solicitações → Nova Solicitação → "Console Me -
  EMR User"** (needs manager + EMR admin approval; provisioning can take a
  couple of hours).
* `aws` CLI available.

Alternative when qli is unavailable: `make weep-auth` in
`.cursor/skills/databricks-emr-migration/migration-emr-cli/` refreshes the same
role into the default AWS credential chain (`EMR_ENVIRONMENT` picks the account).

## Roles (account → ARN)

| Env | Account ID | Role ARN |
| ----- | ------------ | -------- |
| **prod** | `206390561754` | `arn:aws:iam::206390561754:role/sso_DataAndAnalyticsEMRUser_staff` |
| **forno** | `713278628093` | `arn:aws:iam::713278628093:role/sso_DataAndAnalyticsEMRUser_staff` |

Default region: **`us-east-1`**.

## Log layout

DAG Builder sets LogUri to:

```text
s3://artifacts.s3.data.quintoandar.com.br/emr/logs/dags/<dag_id>/<cluster_id>/
├── steps/s-<step_id>/
│   ├── stderr.gz      ← driver + Python traceback
│   ├── stdout.gz      ← job INFO lines (often has the clean Traceback)
│   └── controller.gz
├── containers/application_<yarn_app_id>/
│   └── container_*/{stderr,stdout}.gz
└── node/…             ← instance bootstrap output (init script logs)
```

Ad-hoc CLI runs (`emr-run` skill, migration validation) log under
`emr/logs/cli/<cluster_id>/…` instead of `emr/logs/dags/<dag_id>/…`.

Which folder answers which question:

* **steps/** — step failed: start here (driver stdout/stderr + EMR controller).
* **containers/** — driver blames executors (OOM, task failures).
* **node/** — cluster never became usable / step never started: bootstrap
  (init script) output.

Finding the ids: the Airflow **submit-steps task log** shows the `StepId=s-…`
and the terminal state, and usually the S3 prefix + `j-…`. EMR operators run
in **deferrable mode** by default, so the polling output lives in the
**Triggerer** log, not the task log. The YARN `application_…` id is usually
inside the step `stderr`. In the AWS Console, the cluster name is
`<dag_id>_<run_id>` and the EMR step name is the Airflow task_id.

Relative path for **`emr-cli dump-logs`** (optional alternative in step 5):

```text
dags/<dag_id>/<cluster_id>/steps/s-<step_id>/
```

## Steps

### 1. Assume the EMR role

```bash
# prod (most Airflow failures)
eval "$(qli aws export 'arn:aws:iam::206390561754:role/sso_DataAndAnalyticsEMRUser_staff')"
# forno
# eval "$(qli aws export 'arn:aws:iam::713278628093:role/sso_DataAndAnalyticsEMRUser_staff')"
aws sts get-caller-identity --output table
```

Credentials are shell-session scoped. Because each Bash tool call is a fresh
shell, run the `eval` and the `aws s3` command **in the same Bash call**
(join with `&&` or a heredoc), or re-export on `ExpiredToken`.

### 2. List and download the step logs

```bash
PREFIX="s3://artifacts.s3.data.quintoandar.com.br/emr/logs/dags/<dag_id>/<cluster_id>/steps/s-<step_id>"
OUT="/tmp/emr-logs/<cluster_id>/<step_id>"   # or your session scratchpad dir
mkdir -p "$OUT"
aws s3 ls "${PREFIX}/" --region us-east-1
aws s3 cp "${PREFIX}/" "$OUT/" --recursive --region us-east-1
gunzip -kf "$OUT"/*.gz
```

### 3. Extract the failure

Prefer **`stdout`** for Python `Traceback` / `AnalysisException`; use
**`stderr`** for YARN / Spark driver noise and the `application_…` id. Use the
**Grep** tool on `$OUT` (pattern below), then **Read** the traceback block:

```text
Traceback|AnalysisException|Exception|Error|Caused by|UNRESOLVED_|exit code
```

Equivalent one-shot Bash if you prefer the shell:

```bash
rg -n "Traceback|AnalysisException|Exception|Error|Caused by|UNRESOLVED_|exit code" "$OUT/stdout" "$OUT/stderr" | head -80
```

### 4. Optional — YARN container logs

If the driver log points at executor OOMs or task failures:

```bash
APP_PREFIX="s3://artifacts.s3.data.quintoandar.com.br/emr/logs/dags/<dag_id>/<cluster_id>/containers/application_<id>"
aws s3 ls "${APP_PREFIX}/" --recursive --region us-east-1
aws s3 cp "${APP_PREFIX}/" "$OUT/containers/" --recursive --region us-east-1
find "$OUT/containers" -name '*.gz' -exec gunzip -kf {} \;
```

### 5. Optional — emr-cli

The `emr-cli dump-logs` subcommand prints the objects under the configured
`dump_logs_base_uri` for you (creds must already be exported from step 1). Run
it through **uv** — never a bare interpreter:

```bash
uv run --directory packages/emr-cli emr-cli dump-logs \
  dags/<dag_id>/<cluster_id>/steps/s-<step_id>/stderr.gz
```

If a PEX/binary has been built at `packages/emr-cli/dist/emr-cli`, that also works:

```bash
packages/emr-cli/dist/emr-cli dump-logs dags/<dag_id>/<cluster_id>/steps/s-<step_id>/
```

### 6. Optional — Spark UI (stage/executor-level analysis)

When raw logs aren't enough (skew, slow stages, shuffle problems), point the
user to the Spark UI — this part is Console-only, not automatable from here:

* **Live** (cluster still up): AWS Console → EMR → Clusters → \<cluster\> →
  **Application user interfaces** → YARN ResourceManager → your application →
  Application Master → Spark UI. Requires SSO/VPN on the QuintoAndar network.
* **Persistent** (cluster terminated): AWS Console → EMR → **Persistent
  application UIs** → Spark History Server for the `j-…` id. Available for
  ~30 days after termination (event log lives under the same LogUri prefix).

## Known failure patterns

* **Step never appears on the cluster** — IAM scoping: EMR EC2 actions require
  the tag `for-use-with-amazon-emr-managed-policies=true`. The DAG Builder and
  the repo CLIs auto-add it; hand-rolled clusters must add it themselves.
* **SQL parse error only on EMR** — almost always a Databricks-only construct
  (`QUALIFY`, `column:key` JSON access, …). Use the `databricks-emr-sql-lint`
  skill on the query.
* **Behavior differs on EMR with no obvious Databricks-ism** — check
  `spark_conf`: keys starting with `spark.databricks.*` are **silently
  dropped** on EMR by design; adjacent settings may still matter.
* **Rerunning a failed step** — clearing the failed Airflow task re-submits
  with a fresh StepId. The `terminate-emr-cluster` task has
  `trigger_rule=all_done`, so the cluster is usually already gone — clear from
  `create-cluster` so a new cluster is provisioned.

## Hard rules

* **Read-only**: `aws s3 ls` / `aws s3 cp` (download) only. Never `rm`, `mb`,
  `rb`, `mv`, or put objects.
* Never print or commit exported `AWS_*` secrets.
* Do not use Databricks job-run APIs (or the Databricks MCP) for these
  failures — EMR steps write to the artifacts S3 prefix above, not Databricks.
* Airflow "Reason: Unknown Error" alone is useless; always resolve via S3 step
  logs.

## Quick diagnosis checklist

1. Airflow → S3 prefix / `j-` / `s-`
2. Export EMR role for the right env
3. Download `stdout.gz` + `stderr.gz`
4. Grep for the failure pattern; Read the traceback block
5. Only then dig into YARN container logs if the driver blames executors
