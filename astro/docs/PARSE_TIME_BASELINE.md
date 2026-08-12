# Astro-dev DAG parse-time baseline (2026-07-21)

Baseline captured from dag-processor "DAG File Processing Stats" logs **before**
the parse-optimization stack (PRs A–D) is deployed to the Astro "dev" deployment.

## How to re-measure the stack

The primary comparison is the baseline below versus the fully deployed stack.
Per-PR snapshots are optional diagnostics: deploy timing may not leave enough
steady-state processor cycles between merges to make them representative.

1. After the full stack is deployed and stable, download 2+ fresh processor log
   snippets (same format and comparable cycle coverage as `dag_parse*.log`).
2. Run:

```bash
uv run --no-project python scripts/analysis/parse_processor_logs.py \
  --before ~/Downloads/dag_parse_baseline.log \
  --after  ~/Downloads/dag_parse_after.log
```

Or the compact summary used in the investigation:

```bash
uv run --no-project python - <<'PY'
# paste /tmp/parse_log_analysis.py logic against new logs
PY
```

3. Fill the whole-stack after column below. Record a per-PR snapshot only when
   it contains a complete, steady-state processing cycle.

## Baseline (dev deploy, bietlejuice in image, no A–D)

Source: `~/Downloads/dag_parse{1..4}.log` (2026-07-21).

| Metric | Baseline (dev) | After full stack | Optional per-PR notes |
|---|---|---|---|
| Files | 872 | 870 (0 errors) | |
| Mean parse (s) | 3.33 | 2.50 | |
| Median parse (s) | 2.61 | 1.90 | |
| p90 parse (s) | 8.01 | 5.27 | CPU-contention noise; see below |
| Max parse (s) | 20.49 (`amplitude_subpartitioned`) | 12.65 (`amplitude_subpartitioned`) | |
| Mean DB queries / file | 49.7 | 28.6 | |
| Max DB queries | 745 (`amplitude_subpartitioned`) | 170 (`reverse_birdie`); amplitude 17 | alias batching confirmed |
| Linear fit | 2.42s + 18.2ms/query | 2.27s + 8.0ms/query | |
| Approx cycle span | ~12–16 min | ~7–8 min | |

After source: `~/Downloads/dag_parse_post_stack{1,2}.log` (2026-07-21,
~40–70 min post-deploy). Total parse time over the 870 common DAGs:
2838s → 2173s (−23.4%).

The per-snapshot 9–11s "regression" cohort rotated between snapshots, was
uniformly distributed across each cycle, and did not correlate with DB query
counts. It was CPU-contention noise from parse children sharing the 3.5-vCPU
cap. Dag-processor CPU remained at ~85% because the default 30s file interval
made files eligible again before the cycle drained.

## Local verification already done (pre-deploy)

| Check | Result |
|---|---|
| Prewarm gate unit tests | pass |
| CSafeLoader FileService tests | pass |
| Validation codegen (104 twins emitted locally; gitignored) | pass |
| Alias batching patch dry-run on Airflow 2.11.2 | applies cleanly |
| Alias SELECTs for amplitude (steady-state) | **365 → 1** IN query |

## Local intercept profile (Round 2)

`scripts/analysis/profile_dag_parse.py` profiles `DagBag` import plus
`SerializedDAG.to_dict` in the Astro Runtime 13.4 image. Each file was run in a
fresh container/process after initializing a local metadata DB and explicitly
running the same manager prewarm used in production. Round 2 manifests were
generated and trusted. See the script docstring for the reproducible command.

| Representative DAG | Tasks | Total | DagBag parse | Serialization |
|---|---:|---:|---:|---:|
| `amplitude_subpartitioned` | 1,127 | 5.34s | 0.74s | 4.59s |
| `gsheets_growth` | 465 | 2.04s | 0.50s | 1.54s |
| `enrich_recupera` | 22 | 0.55s | 0.45s | 0.09s |
| `dw_country` | 8 | 0.17s | 0.13s | <0.05s |

Findings:

- Large DAGs are now dominated by Airflow serialization, especially JSON
  Schema validation of operator params. Manifests and declaration warming
  cannot materially reduce their remaining per-DAG work.
- Manifest-backed path discovery is below 1ms in all four profiles.
- The small representative takes 0.17s locally versus the production linear
  intercept of 2.27s. The unaccounted cost is outside DAG construction:
  parse-child scheduling/fork lifecycle and CPU contention. This satisfies the
  gate for testing bundled generated modules: fewer files amortize that
  lifecycle without changing DAG semantics.
- Absolute local timings are diagnostic only; hosted CPU and metadata-DB
  latency differ. Compare relative phase shares and use processor logs for the
  deployment decision.

Bundling gate decision: **proceed**. The production intercept plus the 0.17s
small-DAG local profile shows that most fixed wall time is outside DAG
construction. The Astro-only codegen produces 47 domain bundle files for 827
generated DAGs (maximum 25 DAGs per file), while exact rsync excludes preserve
legacy Python DAGs. Runtime 13.4 loaded and serialized a real 22-DAG/914-task
bundle in 6.1s with no import errors, well below the 120s processor timeout.

Astro development CI (`make create-astro-dag-files`) regenerates parse-time
manifests and domain bundles only — it does **not** emit per-DAG `*_dag.py` /
`*_validation_dag.py` stubs. Forno/prod keep `make create-dag-files`; the
luigijr sandbox keeps `make create-luigijr-dag-files`.

## First-deploy watchlist

- Watch dag-processor logs for hung or crashing parse children, the primary
  signature that a prewarmed import was not fork-safe.
- Confirm the `bietlejuice pre-warm complete` summary appears once in manager
  startup logs and reports plugin and line-folder counts.
- Set `BIETLEJUICE_PREWARM=never` and restart the component to roll back the
  manager prewarm without reverting the image.
- Set `BIETLEJUICE_PREWARM_DECLARATIONS=never` to disable only the per-DAG
  declaration warm. Query-list caches are deliberately not manager-warmed:
  SQL-only DAG bundle updates must be visible without a processor restart.
  Local Runtime 13.4 verification warmed 839 declarations with 0 failures in
  8.1s; the subsequent `dw_country` parse hit the inherited cache and fell from
  0.17s to 0.11s.
- `BIETLEJUICE_PREWARM_DECLARATIONS_TIMEOUT_S` is a soft cumulative budget
  checked between declarations. It does not asynchronously interrupt an
  in-flight local YAML/Cerberus call, which could leave pre-fork state unsafe.
- The line-folder scan is inherited by parse children. A brand-new top-level
  domain delivered only through a DAG bundle requires a dag-processor restart;
  existing domain contents remain safe to update without one.
- Bundled files quarantine individual DAG build failures under the real
  `dag_id` (tag `broken-dag`) so healthy siblings keep loading. Watch the
  `broken-dag` tag and `airflow.notify_broken_dags`; rollback is removing the
  bundle-codegen command and rsync exclude file from the Astro development
  pipeline.
- Migration twin/emr/compare bundles live under
  `_astro_bundles/platform_migration/_*_bundle_*.py`. Watch those import
  errors separately; rollback is documented in the migration cohort section
  below (drop `--bundle-migrations` + `.airflowignore` lines).

## Round 2 deployment measurement

Status: pending deployment of `stack/astro-dev-10` through `14`. Capture at
least two complete steady-state processor snapshots after the stack and
infrastructure PR #41166 (`MIN_FILE_PROCESS_INTERVAL=600`) are live:

```bash
uv run --no-project python scripts/analysis/parse_processor_logs.py \
  --before ~/Downloads/dag_parse_post_stack1.log \
           ~/Downloads/dag_parse_post_stack2.log \
  --after  ~/Downloads/dag_parse_round2_1.log \
           ~/Downloads/dag_parse_round2_2.log \
  --out temp/round2-processor-report.md
```

Round 2 changes file topology from 827 generated stubs to 47 domain bundles.
The analyzer therefore keys files by normalized domain path and reports
topology-independent all-file cycle totals; paired-DAG deltas are explicitly
marked non-representative.

Downsizing decision after measurement:

- Recommend `scheduler_size = "LARGE"` when the 600s interval produces a
  sustained idle period, the complete parse cycle remains below 10 minutes,
  and no bundle approaches the 120s file timeout.
- Keep `EXTRA_LARGE` if the queue does not drain inside 600s or any bundle
  exceeds 90s. Adjust bundle size before reducing compute.
- The actual size change belongs in a separate infrastructure PR after these
  conditions are measured.

## Wonka registry factory parse (2026-07-23)

Baseline vs shared-config + sha256 registry cache, measured with
`scripts/analysis/profile_dag_parse.py` inside `bietlejuice-airflow:local`
against a local-disk seed of the quintoml registry
(`~/Work/quintoml/dist/wonka-registry-seed`, 139 jobs → 271 DAGs / 1480 tasks).
No S3 / STS in this measurement — network cost is additional on the hosted
deployment and is addressed by the sha256-validated disk cache.

| Metric | Before | After |
|---|---:|---:|
| Total (DagBag + serialize) | 26.64s | **8.65s (−67%)** |
| DagBag parse alone | ~20.8s | **2.75s** |
| Serialization | ~5.5s | ~5.7s (floor) |
| `HierarchicalConf.__init__` calls | 278 | ~1–2 |
| DAG / task count | 271 / 1480 | 271 / 1480 |
| Import errors | 0 | 0 |

Root cause: each Wonka workflow created `ConfigurationService(job_name)`, and
Wonka names have no folder under `dags/`, so every build took the Databricks
volume branch and eagerly re-parsed `prod_conf.yml` (~120KB). Fix: shared
`WONKA_SHARED_CONFIG_DAG_NAME = "__wonka__"` sentinel + root-only
`ConfigurationService()` in `OptimizeDeltaTableTaskCreator` (global
`delta_maintenance_state_prefix` key).

Hosted Dev expectation (baseline ~90s wall including serial S3 GETs): roughly
30–45s after image deploy; sha256 cache eliminates per-cycle config GETs when
`MIN_FILE_PROCESS_INTERVAL` (600s) exceeds `WONKA_REGISTRY_TTL` (300s).

## Migration twin/emr/compare cohort (2026-07-24)

The master → development sync brought ~714 standalone
`dags/platform/migration_{twin,emr,compare}_*` Python DAGs (emr-migration-v2
skill output; no `*_declaration.yml`). Domain bundling only covers
declaration DAGs, so these files parsed individually and dominated the cycle.

Source: `~/Downloads/dag_parse_twins1.log` (2026-07-24, post master sync):

| Cohort | Files | Total Last Runtime | Mean |
|---|---:|---:|---:|
| Domain bundles (`_astro_bundles/*`) | 44 | ~1,066s | ~24s |
| `migration_twin_*` | 237 | ~623s | ~2.6s |
| `migration_emr_*` | 237 | ~615s | ~2.6s |
| `migration_compare_*` | 237 | ~572s | ~2.4s |
| Other individuals + Wonka | 38 | ~116s | — |
| **Grand total** | **793** | **~2,992s** | — |

Migration cohort alone: **711 files / ~1,810s (~60% of cycle)** — almost all
fixed per-file processor lifecycle cost (~2.3–2.6s intercept).

### Fix: exec-passthrough Python bundles (Astro-dev only)

`create_dag_files.py --bundle-migrations` (wired into `make create-astro-dag-files`)
groups sorted `platform/migration_{twin,emr,compare}_*/*_dag.py` paths into
`dags/_astro_bundles/platform_migration/_{twin,emr,compare}_bundle_NN.py`
(default 25 DAGs/file). Each bundle `exec`s the real source modules with a
correct `__file__` so `Path(__file__)` lookups and worker re-imports keep
working. Per-DAG files still ship in the rsync payload; `.airflowignore`
stops the processor from parsing them individually:

```
platform/migration_twin_*/
platform/migration_emr_*/
platform/migration_compare_*/
platform/migration_assets/
```

Do **not** add these paths to `astro/generated-dag-excludes.txt` — that list
is only for declaration stubs that domain bundles replace.

Expected after deploy: ~711 individual files → ~29 bundles; migration parse
cost ~1,810s → ~200–350s/cycle; full cycle ~3,000s → ~1,300–1,500s.

### Bundled measurement (2026-07-24)

Source: `~/Downloads/dag_parse_twins_bundled2.log` (complete cycle, 111/111
files, 0 errors):

| Cohort | Before | After | Delta |
|---|---:|---:|---:|
| Files in bag | 793 | **111** | −86% |
| Sum of Last Runtime | 2,992s | **2,233s** | **−760s (−25%)** |
| Migration cohort | 1,810s (711 files) | **850s** (30 bundles) | **−960s (−53%)** |
| Domain bundles | 1,066s | 1,294s | +228s (CPU contention noise) |
| Other + Wonka | 116s | 89s | −27s |

Migration bundles: mean **28.3s**/file (min 10s, max 34s). Plan target of
200–350s was optimistic; remaining fat is inside each `exec`'d module.

### Follow-up: shared root ConfigurationService (2026-07-24)

Same pathology as Wonka: each twin/emr/compare module called
`ConfigurationService(SOURCE_DAG_NAME)` with a distinct name, so the instance
cache never hit — 25 fresh `HierarchicalConf` loads of `prod_conf.yml` per
bundle. Migration DAGs only read environment-global keys
(`datalake_bucket`, `artifacts_bucket`, `databricks_bietlejuice_repo_path`).

Change: `ConfigurationService()` (root-only, cached under `(None, None)`) in
all 714 generated files and the three `emr-migration-v2` Jinja templates.
Pre-change audit found zero source-DAG `*_conf.yml` overrides of those keys.

Local verification (ENVIRONMENT=prod):

| Check | Result |
|---|---|
| `HierarchicalConf.__init__` for 25 twin modules | **25 → 1** |
| Exec 5 twin + 1 compare modules | 0 errors, correct DAG IDs |
| Compiler unit tests | 14 passed |

### Shared-config hosted measurement (2026-07-24)

Source: `~/Downloads/dag_parse_twins_bundled3.log` (complete cycle, 111/111
files, 0 errors) after shared-config deploy:

| Cohort | Bundled2 | Bundled3 (shared config) | Delta |
|---|---:|---:|---:|
| Sum of Last Runtime | 2,233s | **1,146s** | **−49%** |
| Migration cohort | 850s (mean 28.3s) | **74s (mean 2.5s)** | **−91%** |
| Domain bundles | 1,294s | 979s | −24% (less contention) |
| vs pre-bundle (2,992s) | −25% | **−62%** | |

Migration tax: ~60% of the cycle → ~6%. Twin 25s · emr 27s · compare 22s
across 10 bundles each (min 1.2s, max 3.3s). Migration DB queries also fell
18.4k → 3.3k.

```bash
uv run --no-project python scripts/analysis/parse_processor_logs.py \
  --before ~/Downloads/dag_parse_twins_bundled2.log \
  --after  ~/Downloads/dag_parse_twins_bundled3.log \
  --out temp/migration-shared-config-processor-report.md
```

### DB-query investigation (no patch)

Bundles showed ~680 DB queries / 25 DAGs (~27/DAG) vs ~11/DAG individually.
Local `DagBag.sync_to_db` probe on 5 twin DAGs: queries are inherent per-DAG
serialization upserts (`serialized_dag`, plain `dataset` SELECT/INSERT,
outlet references). Twin/compare DAGs use `Dataset(...)` outlets/schedules,
**not** `DatasetAlias`, so `astro/parse-alias-batching.patch` does not apply.
No further Airflow patch for this cohort.

### Re-measure (bundling)

```bash
uv run --no-project python scripts/analysis/parse_processor_logs.py \
  --before ~/Downloads/dag_parse_twins1.log \
  --after  ~/Downloads/dag_parse_twins_bundled1.log \
           ~/Downloads/dag_parse_twins_bundled2.log \
  --out temp/migration-bundle-processor-report.md
```

### Rollback

1. Remove `--bundle-migrations` from the `create-astro-dag-files` Makefile
   target (and/or stop generating `platform_migration/` bundles).
2. Remove the four `platform/migration_*` lines from `dags/.airflowignore`.
3. Redeploy the Astro DAG bundle.
4. Shared-config rollback: restore `ConfigurationService(SOURCE_DAG_NAME)` /
   `ConfigurationService("<dag>")` in the three templates and regenerate (or
   revert the generated-file commit).

### Attention points

- Bundle import error blocks all DAGs in that chunk (same blast radius as
  domain bundles; these are manually triggered validation DAGs).
- Worker task start re-execs the whole bundle (~10–30s once per task) —
  acceptable for validation DAGs.
- Compare DAGs mutate `sys.path` to import `migration_assets`; that remains
  idempotent under exec-passthrough.
- UI fileloc becomes the bundle path, consistent with domain bundles.
- Forno/prod keep parsing the per-DAG files directly (`make create-dag-files`
  does not run `--bundle-migrations`), but still benefit from the shared
  `ConfigurationService()` rewrite in the generated sources.
- Editing generated migration files on development may conflict at the next
  master sync; templates are updated so regenerations stay consistent.

## Success targets (from plan)

- Heavy files: 10–20s → ~2–3s
- Full cycle: 12–16 min → ~3–4 min
- Dag-processor CPU well below Extra Large cap
