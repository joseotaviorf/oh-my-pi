-- Current state of Allocation Tool tags, built from per-entity snapshot exports
-- (*-snapshot-*, envelope with `records`). Each run parses the files of its load
-- window, keeps the latest version per tag id and MERGEs into the clean table
-- on id_tag (merge_on in the declaration). Records are parsed as MAP<STRING,STRING>
-- so new upstream fields never break the load; deletions are soft (is_active), so
-- the latest snapshot is the whole truth.
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
        datalake_allocation_tool_raw.tags
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
        snapshot_records
)
SELECT
    record['id'] AS id_tag,
    record['group_id'] AS id_group,
    record['created_by_id'] AS id_created_by,
    record['deactivated_by'] AS id_deactivated_by,
    record['name'] AS tag_name,
    file_name,
    CAST(record['is_active'] AS BOOLEAN) AS is_active,
    CAST(record['is_sample'] AS BOOLEAN) AS is_sample,
    CAST(record['deactivated_at'] AS TIMESTAMP) AS ts_deactivated,
    CAST(record['created_date'] AS TIMESTAMP) AS ts_created,
    CAST(record['updated_date'] AS TIMESTAMP) AS ts_updated,
    ts_export_generated,
    ts_file_modified,
    ts_load
FROM
    latest_record
WHERE
    rn_record = 1
