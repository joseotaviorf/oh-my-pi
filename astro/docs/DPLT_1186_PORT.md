# DPLT-1186 parse-time optimizations — port from PR #22522

Port of high-value parse-time optimizations from `origin/jose.rferreira/improve_dag_processor2` onto the `packages/` layout (stack `stack/astro-dev-09-dplt-1186-cache`).

## Already on this stack (not re-ported)

| Optimization | Location |
|---|---|
| Prewarm via `astro/config/airflow_local_settings.py` | `astro/config/` |
| CSafeLoader in FileService + yaml.safe_load shim | `packages/bietlejuice-core/.../file_service.py` |
| Validation twin split (`*_validation_dag.py`) | `packages/bietlejuice-compiler/.../create_dag_files.py` |
| Airflow DatasetAlias batching patch | `astro/parse-alias-batching.patch` |
| ConfigurationService `_instance_cache` / `__new__` | Merged via PR #22384 |

## Ported in this change

### 1. Lazy HierarchicalConf load (`ConfigurationService`)

- **File:** `packages/bietlejuice-core/src/bietlejuice/services/configuration_service.py`
- Defers `super().__init__(searched_paths)` until first config access via `_ensure_config_loaded`, `__getattribute__` for `_configs`/`configs`, and `get_config`.
- Preserves `BIETLEJUICE_CONFIG_ROOT`, Databricks volume fallback, and existing `_instance_cache`.
- **Tests:** `packages/bietlejuice-core/test/unit/services/test_configuration_service.py`

### 2. DAG declaration cache by `dag_name`

- **File:** `packages/bietlejuice-core/src/bietlejuice/base/airflow/dag_builders/main_builder/dag_declaration/dag_yaml_parser.py`
- Module-level `@lru_cache` function `_parse_dag_declaration(dag_name)` wraps the full declaration+cluster merge/validation path (including split cluster YAML support on current master).
- Invalidation via `DAGPackagesPathService.clear_path_caches()`.
- **Tests:** cache isolation + shared-by-name test in `test_dag_yaml_parser.py`

### 3. Manifest-based path lookups

- **Runtime:** `packages/bietlejuice-core/src/bietlejuice/base/service/dag_packages_path_service.py`
  - `_manifest_is_fresh()` helper
  - `.table_manifest` for `list_queries_files_in_composer` (`@lru_cache`, returns `tuple`)
  - `.data_quality_manifest` for `list_data_quality_table_paths_in_composer` (`@lru_cache`)
  - Extended `clear_path_caches()` for all LRU caches + declaration parse cache
- **Metadata:** `packages/bietlejuice-core/src/bietlejuice/services/dag_metadata_service.py`
  - `.metadata_manifest` support + `@lru_cache` on `list_metadata_table_paths`
- **CI scripts** (adapted to `bietlejuice.base.paths.DAG_PACKAGES_ROOT`):
  - `packages/bietlejuice-compiler/scripts/ci_cd/generate_query_manifests.py`
  - `packages/bietlejuice-compiler/scripts/ci_cd/generate_metadata_manifests.py`
  - `packages/bietlejuice-compiler/scripts/ci_cd/generate_data_quality_manifests.py`
- All manifest reads fall back to filesystem glob when manifest is absent or stale (directory mtime newer than manifest).
- **Tests:** manifest vs glob/stale cases in `test_dag_packages_path_service.py`

## Deferred (and why)

| Item | Reason |
|---|---|
| **Lazy task creator mixins** (`JobClusterTaskCreatorMixin`, `LazyTaskCreatorFactoryMixin`) | PR refactored 13+ workflow classes to use `@property`-based lazy creators; current stack still uses eager `_initialize_task_creators` in each workflow. Porting would be a large cross-package rewrite with high regression risk for modest incremental gain on top of items 1–3. |
| **`WONKA_SHARED_CONFIG_DAG_NAME`** | **Ported** in `perf/wonka-parse-time-optimization` (see `astro/docs/PARSE_TIME_BASELINE.md` Wonka section). Shared `__wonka__` ConfigurationService + sha256 registry cache. |
| **Committing generated manifest files into `dags/`** | Scripts are ported; manifest files themselves are generated artifacts (run scripts in CI or locally before deploy). No mass `dags/**/.table_manifest` commit in this port. |
| **PR `list_artifact_file_paths` manifest shortcut** | PR did not add manifest support to `list_artifact_file_paths`; metadata listing goes through `DAGMetadataService.list_metadata_table_paths` instead. |

## Follow-up (optional)

1. Run manifest generators in CI before DAG package upload:
   ```bash
   uv run --directory packages/bietlejuice-compiler python scripts/ci_cd/generate_query_manifests.py
   uv run --directory packages/bietlejuice-compiler python scripts/ci_cd/generate_metadata_manifests.py
   uv run --directory packages/bietlejuice-compiler python scripts/ci_cd/generate_data_quality_manifests.py
   ```
2. Re-measure parse-time baseline (astro docs A–D) after manifests are committed for high-table-count DAGs.
3. Consider lazy task creator mixins as a separate PR once parse baseline stabilizes.
