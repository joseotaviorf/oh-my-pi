WITH filter_bimester AS (
    SELECT DISTINCT
        ad.year,
        ad.bimester
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    t.id_agent,
    t.id_user,
    t.id_business_unit,
    t.id_share_rule,
    t.program_code,
    t.profile,
    t.bimester_name,
    ap.name,
    ap.email,
    ap.cpf,
    ap.phone_number,
    ap.hub_name,
    t.total_operation_points,
    t.tier_name,
    CAST(t.brokerage_value AS DOUBLE) AS brokerage_value,
    t.year,
    t.bimester
FROM
    datalake_tiers_classification.tiers AS t
JOIN
    datalake_tiers.agent_performance AS ap
        ON ap.id_agent = t.id_agent
        AND ap.bimester = t.bimester
        AND ap.year = t.year
JOIN
    filter_bimester AS fb
        ON fb.bimester = t.bimester 
        AND fb.year = t.year 