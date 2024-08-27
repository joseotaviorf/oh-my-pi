WITH filter_bimester AS (
    SELECT DISTINCT
        ad.year,
        ad.bimester
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_operation_points AS (
    SELECT 
        aop.id_agent,
        aop.id_user,
        aop.id_business_unit,
        aop.bimester_name,
        aop.profile,
        aop.program_code,
        SUM(aop.operation_points) AS total_operation_points,
        aop.year,
        aop.bimester
    FROM 
        datalake_tiers_classification.operation_points AS aop
    GROUP BY ALL
)
SELECT
    aop.id_agent,
    aop.id_user,
    aop.id_business_unit,
    sr.id_share_rule,
    aop.bimester_name,
    aop.profile,
    aop.program_code,
    aop.total_operation_points,
    sr.tier_name,
    sr.brokerage_value,
    aop.year,
    aop.bimester
FROM
    agent_operation_points AS aop
JOIN
    datalake_tiers.hub_share_rule AS sr
        ON aop.program_code = sr.program_code
        AND aop.id_business_unit = sr.id_business_unit
        AND aop.total_operation_points >= sr.min_score
        AND aop.total_operation_points <= COALESCE(sr.max_score, aop.total_operation_points)
        AND sr.bimester = aop.bimester 
        AND sr.year = aop.year 
JOIN
    filter_bimester AS fb
        ON fb.bimester = aop.bimester 
        AND fb.year = aop.year 