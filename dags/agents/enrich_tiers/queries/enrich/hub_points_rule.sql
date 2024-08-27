WITH points_rule AS (
    SELECT
        pr.id AS id_points_rule,
        pr.id_external_condition AS id_business_unit,
        pr.program_code,
        pr.operation,
        pr.trigger,
        pr.points,
        pr.max_points,
        pr.dt_start,
        IF(pr.dt_start = DATE("2024-05-01"), DATE("2024-06-30"), pr.dt_end) AS dt_end,
        pr.ts_created,
        pr.ts_updated
    FROM
        datalake_big_agent_clean.points_rule_aud AS pr
    WHERE
        pr.external_condition_type = "HUB"
        AND pr.status = "VALID"
)
SELECT
    pr.id_points_rule,
    pr.id_business_unit,
    pr.program_code,
    pr.operation,
    pr.trigger,
    pr.points,
    pr.max_points,
    pr.ts_created,
    pr.ts_updated,
    ad.year,
    ad.bimester
FROM
    points_rule AS pr
JOIN
    datalake_quintoandar.aux_date AS ad
        ON ad.date BETWEEN pr.dt_start AND pr.dt_end
WHERE
    ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY   
    pr.ts_updated = LAST(pr.ts_updated) OVER (PARTITION BY pr.id_points_rule)