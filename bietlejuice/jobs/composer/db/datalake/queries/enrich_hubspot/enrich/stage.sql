WITH numbered_stage_history AS (
    SELECT *,
        ROW_NUMBER() OVER(PARTITION BY id_stage ORDER BY ts_updated DESC) AS rw
    FROM
        datalake_hubspot.stage_history
)
SELECT
    id_stage,
    id_pipeline,
    label,
    metadata,
    display_order,
    is_deal_stage,
    is_ticket_stage,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    numbered_stage_history
WHERE
    rw = 1
    AND NOT is_archived