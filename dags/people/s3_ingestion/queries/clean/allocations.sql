-- Append-only log of every allocation version the Allocation Tool has exported.
-- NOTE the grain: one row per allocation AND version, not one row per allocation.
-- This is the ONLY place the raw envelopes are parsed. The app exports a full
-- snapshot on every run (*-snapshot-*, envelope with `records`); both
-- `allocations` (current state) and the People allocation history derive from this
-- table, so a new upstream field is added here once.
-- Records are parsed as MAP<STRING,STRING> so new fields never break the load.
-- One row per allocation id and version timestamp; the MERGE in the declaration
-- makes reruns and out-of-order backfills idempotent.
-- Partitioned by the raw INGESTION date, not by ts_version: the Airflow load
-- window is expressed in ingestion dates, so a late or retried export whose
-- generated_at is older than the window must still fall inside it -- otherwise
-- downstream consumers filtering on the window would silently skip the file.
WITH snapshot_records AS (
    SELECT
        record,
        'snapshot' AS export_type,
        MAKE_DATE(year, month, day) AS dt_ingestion,
        CAST(
            GET_JSON_OBJECT(raw_content, '$.generated_at') AS TIMESTAMP
        ) AS ts_export_generated,
        file_name,
        ts_file_modified,
        ts_load
    FROM
        datalake_allocation_tool_raw.allocation
        LATERAL VIEW EXPLODE(
            FROM_JSON(
                GET_JSON_OBJECT(raw_content, '$.records'),
                'ARRAY<MAP<STRING,STRING>>'
            )
        ) exploded AS record
    WHERE
        MAKE_DATE(year, month, day)
            BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        -- Only the per-entity envelope has `records`; legacy bare arrays and
        -- unified envelopes sharing this prefix don't, and stay ignored.
        AND GET_JSON_OBJECT(raw_content, '$.records') IS NOT NULL
),
versioned_records AS (
    SELECT
        record,
        export_type,
        dt_ingestion,
        ts_export_generated,
        file_name,
        ts_file_modified,
        ts_load,
        -- Exports carrying no `generated_at` fall back to the S3 modification
        -- time so every version has a single, non-null ordering key.
        COALESCE(ts_export_generated, ts_file_modified) AS ts_version
    FROM
        snapshot_records
),
deduplicated_versions AS (
    SELECT
        record,
        export_type,
        dt_ingestion,
        ts_export_generated,
        file_name,
        ts_file_modified,
        ts_load,
        ts_version,
        ROW_NUMBER() OVER (
            PARTITION BY
                record['id'],
                ts_version
            ORDER BY
                ts_file_modified DESC,
                file_name DESC
        ) AS rn_version
    FROM
        versioned_records
)
SELECT
    record['id'] AS id_allocation,
    record['employee_id'] AS id_employee,
    record['group_id'] AS id_group,
    record['tag_id'] AS id_tag,
    record['allocated_by'] AS id_allocated_by,
    record['created_by_id'] AS id_created_by,
    record['employee_name'] AS employee_name,
    record['gestor_name'] AS manager_name,
    record['group_name'] AS group_name,
    record['tag_name'] AS tag_name,
    record['chapter'] AS chapter,
    record['vertical'] AS vertical,
    record['team'] AS team,
    record['status'] AS status,
    export_type,
    file_name,
    record['fl_lider'] = '1' AS is_leader,
    CAST(record['is_sample'] AS BOOLEAN) AS is_sample,
    CAST(record['allocated_at'] AS TIMESTAMP) AS ts_allocated,
    CAST(record['created_date'] AS TIMESTAMP) AS ts_created,
    CAST(record['updated_date'] AS TIMESTAMP) AS ts_updated,
    ts_version,
    ts_export_generated,
    ts_file_modified,
    ts_load,
    dt_ingestion,
    YEAR(dt_ingestion) AS year,
    MONTH(dt_ingestion) AS month,
    DAY(dt_ingestion) AS day
FROM
    deduplicated_versions
WHERE
    rn_version = 1
