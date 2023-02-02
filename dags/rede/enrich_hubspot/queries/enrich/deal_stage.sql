WITH exploded_stages AS (
    SELECT
        id_deal::BIGINT,
        EXPLODE(id_stage_history) AS stage_struct
    FROM
        datalake_hubspot.deal
),
calculated_end_timestamps AS (
    SELECT 
        id_deal,
        stage_struct.value::BIGINT AS id_stage,
        stage_struct['updatedByUserId'] AS id_user_updated_by,
        stage_struct['sourceType'] AS source_type,
        stage_struct.timestamp AS ts_stage_started,
        LEAD(stage_struct.timestamp) OVER (PARTITION BY id_deal ORDER BY stage_struct.timestamp) AS ts_stage_ended
    FROM
        exploded_stages
)
SELECT
    cet.id_deal,
    cet.id_stage,
    s.id_pipeline,
    id_user_updated_by,
    source_type,
    DATEDIFF(COALESCE(cet.ts_stage_ended, NOW()), cet.ts_stage_started) AS days_in_stage,
    cet.ts_stage_started,
    cet.ts_stage_ended
FROM
    calculated_end_timestamps AS cet
JOIN
    datalake_hubspot.stage AS s
        ON cet.id_stage = s.id_stage