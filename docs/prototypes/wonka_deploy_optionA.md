# Prototype: Wonka deploy option A — config registry + parse-time factory

**Branch:** `proto/wonka-deploy-optA`
**Pair:** quintoml `proto/wonka-deploy-optA`

## Idea

quintoml ships **data, not Python**. Its CI publishes one `config.json` per
Wonka job (`{job_name, job_module, job_config, build_info}`) plus a single
`manifest.json` to `<artifacts_bucket>/quintoml/registry/`. One service in the
bi-etl bag reads the manifest at parse time, validates each config against a
Cerberus schema, and builds the DAGs via `FactoryDispatcher` — no quintoflow
import, no `.py` shims from another team's CI, no Airflow deploy on model
release (the immutable commit-SHA `artifact_path` lives inside the config).

## What changed here

| File | Change |
|------|--------|
| [`packages/bietlejuice-airflow/src/bietlejuice/services/wonka_registry_service.py`](../../packages/bietlejuice-airflow/src/bietlejuice/services/wonka_registry_service.py) | all logic: schema, TTL cache, checksums, DAG build (unit-tested in CI) |
| [`dags/quintoml/wonka_registry_factory.py`](../../dags/quintoml/wonka_registry_factory.py) | thin parse-time entry point (ships in the DAG bag) |
| [`packages/bietlejuice-airflow/test/unit/services/test_wonka_registry_service.py`](../../packages/bietlejuice-airflow/test/unit/services/test_wonka_registry_service.py) | validation / build / failure-semantics tests |

## Environment

| Var | Default | Meaning |
|-----|---------|---------|
| `WONKA_REGISTRY_ENABLED` | `1` | kill switch — set `0` to disable without a code revert |
| `WONKA_REGISTRY_URI` | `ConfigurationService` `artifacts_bucket` + `quintoml/registry/manifest.json` | manifest URI override (tests / ad-hoc) |
| `WONKA_REGISTRY_TTL` | `300` | S3 cache TTL seconds |
| `WONKA_REGISTRY_CACHE` | `/tmp/wonka_registry_cache` | local cache directory |
| `WONKA_REGISTRY_ROLE_ARN` | unset | optional IAM role to `sts:AssumeRole` before S3 reads |

No environment is hardcoded: the default URI resolves through
`ConfigurationService` (`prod_conf.yml` / `forno_conf.yml` per the
deployment's `ENVIRONMENT`).

### S3 auth (mirror prod's assume-role pattern)

Parse-time registry fetches run on the scheduler / dag-processor pods, which
use Astronomer's **default** managed workload identity (e.g.
`astro-stellar-potential-3761` on the Data and AI Dev deployment). Do **not**
set Astro's `desired_workload_identity` to a customer role — that switches the
deployment into OIDC/`AssumeRoleWithWebIdentity` mode and requires an IAM
OIDC provider we do not maintain for this path.

Instead, set `WONKA_REGISTRY_ROLE_ARN` to
`arn:aws:iam::206390561754:role/airflow-prod-role`. The service calls
`sts:AssumeRole` with that ARN (session name `wonka-registry-dag-parse`)
before creating its S3 client. The role's trust policy already allows both
Astro identities (`astro-stellar-potential-3761` for Dev,
`astro-amateur-crater-7886` for Prod), and its policy already grants read on
`artifacts.s3.data.quintoandar.com.br/quintoml/*`. Unset (local / tests /
seeding tool) keeps the default boto3 credential chain.

## Failure semantics

| Situation | Behavior |
|-----------|----------|
| Manifest absent (`NoSuchKey` / missing file) | info log, register nothing — registry simply not provisioned for this env |
| Manifest fetch error (network/auth), cache present | serve stale cache (bag keeps its DAGs) |
| Manifest fetch error, **no cache** (cold start) | **raise** → import error; Airflow keeps previously serialized DAGs instead of deleting them |
| `schema_version` ≠ 1 | raise (contract violation, must be coordinated) |
| Per-job: schema-invalid config, checksum mismatch, build error | skip that job, log, continue |
| Validation shadow DAG build fails | log, keep the production DAG (same as the generated shim) |

Note the cold-start caveat: the `/tmp` cache is per-container, so a registry
outage plus a fresh scheduler pod yields an import error (loud, safe) rather
than a silently empty bag.

## Contract enforcement

- Manifest: `schema_version: 1`, `jobs: [{job_key, config_key, sha256}]`.
- Each fetched `config.json` is verified against its manifest `sha256`
  (with one forced cache-bypass refetch to cover a fresh manifest + stale
  cached config).
- Each config validates against the Cerberus schema: `workflow.type: wonka`
  required, `build_info.artifact_path` required, dataset URIs shape-checked.
- Validation shadow DAGs (`validation.cluster`) are built exactly like
  quintoflow's `build_validation_dag()`, including
  `merge_validation_cluster_args`.

## Parse cost

One S3 GET of `manifest.json` per TTL window plus one GET per config on cold
cache; cached reads afterwards. Fits `AIRFLOW__CORE__DAGBAG_IMPORT_TIMEOUT=90`
comfortably.

## Live test on the development deployment

1. Seed the registry (quintoml branch has `src/shell/seed-wonka-registry-local.py`,
   which extracts configs from the deployed prod shims) and sync it to
   `s3://artifacts.s3.data.quintoandar.com.br/quintoml/registry/`.
2. Merge this branch into `development` — `deploy-astro-dags` ships the shim.
   The Dev Astro deployment must expose `WONKA_REGISTRY_ROLE_ARN` (and keep
   Astronomer's default workload identity — no `desired_workload_identity`).
   It already runs `ENVIRONMENT=prod`, so `ConfigurationService` resolves the
   prod artifacts bucket where the registry lives.
3. Verify: no import errors on `wonka_registry_factory.py`, 271
   `quintoml.wonka.*` DAGs present (139 production + 132 validation shadows,
   built offline against the real `FactoryDispatcher` from the seeded
   registry) and **paused** (Airflow default `dags_are_paused_at_creation`).
   The freshness check (`WonkaFreshnessDAGBuilder`) is not in the registry;
   it stays on quintoml's legacy `.py` flow.

**Unpausing any of these DAGs runs a real prod Wonka job** (prod configs, prod
PEX artifact paths). Keep the test parse-level; a first unpause is a
deliberate single-job decision.

## ⚠️ Pre-master-merge checklist

The real production deployment still receives Wonka DAGs as Beethoven-deployed
`.py` shims with the **same DAG ids**. Before `development` merges into
`master`, do one of:

- set `WONKA_REGISTRY_ENABLED=0` on the production deployment, or
- exclude `dags/quintoml/wonka_registry_factory.py` from the prod bag, or
- switch off Beethoven's Wonka DAG deploys (the actual option-A cutover).

Otherwise prod gets duplicate `quintoml.wonka.*` DAG ids.

## Why this survives an Airflow 3 bundles migration

The contract is **data** (validated, checksummed JSON), not remote code.
Bundles would still consume the same registry; only the fetch location might
change.
