WITH numbered_pipeline_history AS (
    SELECT *,
        ROW_NUMBER() OVER(PARTITION BY id_pipeline ORDER BY ts_updated DESC) AS rw
    FROM
        datalake_hubspot.pipeline_history
)
SELECT
    id_pipeline,
    label,
    display_order,
    is_deal_pipeline,
    is_ticket_pipeline,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    numbered_pipeline_history
WHERE
    rw = 1
    AND NOT is_archived