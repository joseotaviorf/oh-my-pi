WITH share_rule AS (
    SELECT
        sr.id AS id_share_rule,
        sr.id_external_condition AS id_business_unit,
        sr.program_code,
        sr.name AS tier_name,
        sr.value AS brokerage_value,
        sr.min_score,
        sr.max_score,
        sr.dt_start,
        IF(sr.dt_start = DATE("2024-05-01"), DATE("2024-06-30"), sr.dt_end) AS dt_end,
        sr.ts_invalidated,
        sr.ts_created,
        sr.ts_updated
    FROM
        datalake_big_agent_clean.share_rule_aud AS sr
    WHERE
        sr.external_condition_type = "HUB"
        AND sr.status = "VALID"
)
SELECT DISTINCT
    sr.id_share_rule,
    sr.id_business_unit,
    sr.program_code,
    sr.tier_name,
    sr.brokerage_value,
    sr.min_score,
    sr.max_score, 
    sr.ts_created,
    sr.ts_updated,
    ad.year,
    ad.bimester
FROM
    share_rule AS sr
JOIN
    datalake_quintoandar.aux_date AS ad
        ON ad.date BETWEEN sr.dt_start AND sr.dt_end
WHERE
    ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY   
    sr.ts_updated = LAST(sr.ts_updated) OVER (PARTITION BY sr.id_share_rule)