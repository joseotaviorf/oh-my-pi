-- Current state of Allocation Tool allocations, built incrementally: the app
-- exports one initial per-entity snapshot (*-snapshot-*, envelope with `records`)
-- and afterwards only modifications, as unified delta files (full records of every
-- allocation changed since the watermark). Each run parses the files of its load
-- window, keeps the latest version per allocation id and MERGEs into the clean
-- table on id_allocation (merge_on in the declaration). Records are parsed as
-- MAP<STRING,STRING> so new upstream fields never break the load; deletions are
-- soft (status), so snapshot + deltas are the whole truth.
WITH snapshot_records AS (
    SELECT
        record,
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
delta_records AS (
    SELECT
        record,
        CAST(
            GET_JSON_OBJECT(raw_content, '$.generated_at') AS TIMESTAMP
        ) AS ts_export_generated,
        file_name,
        ts_file_modified,
        ts_load
    FROM
        datalake_allocation_tool_raw.delta
        LATERAL VIEW EXPLODE(
            FROM_JSON(
                GET_JSON_OBJECT(raw_content, '$.allocations'),
                'ARRAY<MAP<STRING,STRING>>'
            )
        ) exploded AS record
    WHERE
        MAKE_DATE(year, month, day)
            BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
unioned_records AS (
    SELECT
        record,
        ts_export_generated,
        file_name,
        ts_file_modified,
        ts_load
    FROM
        snapshot_records
    UNION ALL
    SELECT
        record,
        ts_export_generated,
        file_name,
        ts_file_modified,
        ts_load
    FROM
        delta_records
),
latest_record AS (
    SELECT
        record,
        ts_export_generated,
        file_name,
        ts_file_modified,
        ts_load,
        ROW_NUMBER() OVER (
            PARTITION BY record['id']
            ORDER BY
                ts_export_generated DESC,
                ts_file_modified DESC,
                file_name DESC
        ) AS rn_record
    FROM
        unioned_records
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
    file_name,
    record['fl_lider'] = '1' AS is_leader,
    CAST(record['is_sample'] AS BOOLEAN) AS is_sample,
    CAST(record['allocated_at'] AS TIMESTAMP) AS ts_allocated,
    CAST(record['created_date'] AS TIMESTAMP) AS ts_created,
    CAST(record['updated_date'] AS TIMESTAMP) AS ts_updated,
    ts_export_generated,
    ts_file_modified,
    ts_load
FROM
    latest_record
WHERE
    rn_record = 1
