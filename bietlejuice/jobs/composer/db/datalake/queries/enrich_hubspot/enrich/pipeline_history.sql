WITH united_pipelines AS (
    SELECT
        id_pipeline,
        label,
        display_order,
        TRUE AS is_deal_pipeline,
        FALSE AS is_ticket_pipeline,
        is_archived,
        ts_archived,
        ts_created,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_hubspot_clean.deal_pipeline
    UNION ALL
    SELECT
        id_pipeline,
        label,
        display_order,
        FALSE AS is_deal_pipeline,
        TRUE AS is_ticket_pipeline,
        is_archived,
        ts_archived,
        ts_created,
        ts_updated,
        year,
        month,
        day
    FROM
        datalake_hubspot_clean.ticket_pipeline
),
pipelines_redundancies_numbered AS (
    SELECT *,
        ROW_NUMBER() OVER(
            PARTITION BY 
                id_pipeline,
                label,
                display_order,
                is_deal_pipeline,
                is_ticket_pipeline,
                is_archived,
                ts_archived,
                ts_created
            ORDER BY 
                ts_updated DESC
        ) AS rw
    FROM
        united_pipelines
)
SELECT
    id_pipeline::BIGINT,
    label,
    display_order::INT,
    is_deal_pipeline,
    is_ticket_pipeline,
    is_archived,
    ts_archived,
    ts_created,
    ts_updated,
    year,
    month,
    day
FROM
    pipelines_redundancies_numbered
WHERE
    rw = 1