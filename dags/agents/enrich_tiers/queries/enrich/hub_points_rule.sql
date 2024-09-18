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
        CASE
            -- These periods came without an end date filled in during the testing of the solution implementation, which is why we declared the end date. 
            -- However, this should not occur for future periods and, if it does, it should not be corrected by Data.
            WHEN pr.dt_start = DATE("2024-05-01") THEN DATE("2024-06-30")
            WHEN pr.dt_start = DATE("2024-07-01") THEN DATE("2024-08-31")
            ELSE pr.dt_end
        END AS dt_end,
        pr.ts_created,
        pr.ts_updated
    FROM
        datalake_big_agent_clean.points_rule AS pr
    WHERE
        pr.external_condition_type = "HUB"
        AND pr.status = "VALID"
)
SELECT DISTINCT
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
    pr.ts_updated = LAST(pr.ts_updated) OVER (PARTITION BY pr.id_points_rule, ad.year, ad.bimester)