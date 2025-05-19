WITH exploded_stages AS (
    SELECT
        EXPLODE(stages) AS stage_struct,
        id_pipeline,
        TRUE AS is_deal_stage,
        FALSE AS is_ticket_stage
    FROM
        datalake_hubspot_clean.deal_pipeline
    UNION ALL
    SELECT
        EXPLODE(stages) AS stage_struct,
        id_pipeline,
        FALSE AS is_deal_stage,
        TRUE AS is_ticket_stage
    FROM
        datalake_hubspot_clean.ticket_pipeline
)
SELECT
    stage_struct.id::BIGINT AS id_stage,
    id_pipeline::BIGINT AS id_pipeline,
    stage_struct.label AS label,
    stage_struct.metadata AS metadata,
    stage_struct.display_order::INT AS display_order,
    is_deal_stage,
    is_ticket_stage,
    stage_struct.archived AS is_archived,
    stage_struct.archived_at AS ts_archived,
    stage_struct.created_at AS ts_created,
    stage_struct.updated_at AS ts_updated,
    YEAR(stage_struct.updated_at) AS year,
    MONTH(stage_struct.updated_at) AS month,
    DAY(stage_struct.updated_at) AS day
FROM
    exploded_stages