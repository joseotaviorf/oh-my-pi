WITH filter_bimester AS (
    SELECT DISTINCT
        ad.year,
        ad.bimester
    FROM 
        datalake_quintoandar.aux_date AS ad
    WHERE
        ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
agent_performance AS (
    SELECT
        ap.id_agent,
        ap.id_user,
        ap.id_business_unit,
        ap.bimester_name,
        ap.profile,
        IF(ap.profile = "Broker", "SALE_AGENT", "NEGOTIATION_EXECUTIVE") AS program_code,
        STACK(
            7,
            CAST(ap.total_regular_offer_signed AS DOUBLE), "CCV",
            CAST(ap.total_offer_signed_with_tqc AS DOUBLE), "CCV_TQC",
            CAST(ap.total_offer_signed_with_ciq AS DOUBLE), "CCV_CIQ",
            CAST(ap.total_first_listing AS DOUBLE), "FIRST_LISTING",
            ROUND(ratio_offer_sent_to_signed * 100, 0), "OS2CCV_BY",
            CAST(ap.total_offer_signed_with_demand_supply_capture AS DOUBLE), "CCV_TQC_CIQ",
            CAST(ap.total_gross_merchandise_volume AS DOUBLE), "GMV"
        ) AS (performance_points, operation),
        ap.year,
        ap.bimester
    FROM
        datalake_tiers.agent_performance AS ap
    WHERE   
        ap.business_context = "SALE"
)
SELECT
    ap.id_agent,
    ap.id_user,
    ap.id_business_unit,
    pr.id_points_rule,
    ap.bimester_name,
    ap.profile,
    pr.program_code,
    ap.operation,
    ap.performance_points,
    CASE
        WHEN INT(ap.performance_points/pr.trigger) * pr.points > pr.max_points THEN pr.max_points
        ELSE INT(ap.performance_points/pr.trigger) * pr.points
    END AS operation_points,
    ap.year,
    ap.bimester
FROM
    agent_performance As ap
JOIN
    datalake_tiers.hub_points_rule AS pr
        ON ap.program_code = pr.program_code
        AND ap.operation = pr.operation
        AND ap.id_business_unit = pr.id_business_unit
        AND ap.year = pr.year
        AND ap.bimester = pr.bimester
JOIN
    filter_bimester AS fb
        ON fb.bimester = ap.bimester 
        AND fb.year = ap.year 