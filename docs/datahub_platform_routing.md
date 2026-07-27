# DataHub platform routing for the metadata-propagator (DPLT-1679)

Design decisions for making per-table metadata (descriptions, data quality)
land on **all the DataHub platforms where a table actually exists**, instead of
being hardcoded to `trino`.

## Problem

The `metadata-propagator` materialized DataHub metadata on the **wrong /
incomplete** platforms:

- `producer_factory.PLATFORM = "trino"` was hardcoded for documentation and
  data-quality producers, while OpenLineage lineage went to `glue`. So the same
  table's metadata was **split** across platforms, and tables that live only in
  Databricks got **phantom `trino` datasets** (a Trino URN for a table not in
  the Trino catalog).
- The emit library never wrote a `container` aspect, so datasets were
  containerless and DataHub synthesized legacy **string browse paths**.

## Where a table lives (the platform footprint)

Source of truth is the **DAG declaration** (`*_declaration.yml`). A table's
platforms are a property of its FQN (`schema.table`):

- **`databricks` + `glue`: always** — the table is Delta on Databricks and the
  Unity Catalog ↔ AWS Glue sync keeps the Glue Data Catalog populated.
- **`trino`: iff Hive-synced** — resolved from `has_hive_sync`:
  `tables_customization.<table>.has_hive_sync` → `workflow.has_hive_sync` →
  per-type default (**`False` for `core_model`, `True` otherwise**).
- **`query_view`** workflows don't use `has_hive_sync`; their platforms come
  from the `sync` list (`databricks`/`trino`; default `["databricks"]`) — views
  are not Glue-synced.

This lives in `bietlejuice.base.pipeline.platform_resolver.resolve_platforms(...)`
(reuses `query_view_sync`). Descriptions **and** data quality resolve platforms
the same way.

### Why `is_validation` is NOT a factor

Platform membership is a property of the table, not of a run. A validation DAG
run must not be special-cased in the resolver:

- Isolating validation from production is handled by the **target
  environment/host** (forno vs prod propagator), not by dropping platforms.
- A validation DAG run never even creates the data-quality task
  (`base_workflow._check_include_data_quality_task` returns `False` when
  `is_validation`), so the DQ path is never exercised in validation.

## How metadata reaches the platforms (the fix)

End-to-end, backward-compatible, and scoped to the DataHub path only
(`vendor: atlas` is a separate router → Atlas, untouched).

1. **Producers declare `platforms`.** bietlejuice resolves the FQN's platforms
   and sends a `platforms` list in the propagator payload:
   - Descriptions: the CI compiler `upload_metadata_files_into_s3.py` reads the
     DAG declaration and adds `platforms` to `/documentation`.
   - Data quality: the runtime threads a comma-joined `platforms` from
     `DataQualityTestsTaskCreator` → `data_quality_tests.py` (and the
     `data_quality_tests_streaming.py` Kafka consumer) → `DataQualityTestsPipeline`
     → `DatahubQualityMetricsPipeline` payload.

2. **The worker fans out.** `DatasetDocumentationProducer` and
   `QualityMetricsProducer` iterate `payload["platforms"]`, writing to each
   platform. **Opt-in / backward-compatible:** when `platforms` is absent the
   producer keeps the legacy single-target behavior (propagator default =
   `trino`), so non-adopting callers (customer-data-platform, Superset,
   OpenLineage) are unaffected.

3. **Per-platform naming.** The dataset-name prefix differs by platform:
   `trino` → `hive.<schema>.<table>` (Hive catalog); `glue`/`databricks` →
   `<schema>.<table>` (no prefix). In `datahub-api-client-python`,
   `DatasetService.upsert_dataset(platform=..., db=...)` and
   `AssertionService.upsert_assertions(platform=...)` accept the platform per
   call; `db=""` (explicit empty) is now honored for the no-prefix platforms.

4. **Containers.** `DatasetService._emit_container` emits the container
   hierarchy via `datahub.emitter.mcp_builder` (`gen_containers` +
   `add_dataset_to_container`), mirroring the acryl ingestion-source convention
   so it lines up with a future native crawler: **glue/databricks = one level**
   (`database = schema`), **trino = catalog + schema**. Opt-in via
   `emit_container=True`; derived from the name (no AWS/Trino access).

## Repos & branches

| Repo | Branch | Change |
| --- | --- | --- |
| `bi-etl-ejuice` | current work branch | resolver + compiler CI + DQ runtime wiring + `TableAttributes.workflow_args` property |
| `datahub-api-client-python` | `feat/dplt-1679-container-platform-per-call` | `DatasetService` container + per-call platform/db; `AssertionService` per-call platform URN; `DatahubClient.emit_mcp` |
| `metadata-propagator` | `feat/dplt-1679-platforms-fanout` | documentation + DQ producers fan out over `platforms`; payload_creators thread `platforms` |

## Testing

Unit tests at every layer (resolver, both external services, both worker
producers, compiler wiring, DQ runtime payload + task creator). External repos
run on py3.11 + `acryl-datahub==0.10.4.3` + `pydantic<2`; the metadata-propagator's
internal deps install via pip with
`--extra-index-url https://quintoandar.github.io/python-package-server/`.

## Follow-ups (out of scope here)

- Soft/hard-delete the existing phantom `trino` datasets and the `glue`/`s3`
  containerless shells the propagator created before this change.
- Stand up a DataHub **Glue ingestion recipe** so Glue becomes a crawler-backed
  source of truth (today it is only propagator output); then the propagator
  decorates crawler-created datasets instead of creating them.
