WITH new_earnings AS (
    SELECT
        ne.id_earning_source,
        SUM(ne.revenue_percentage) AS revenue_percentage
    FROM
        datalake_big_agent_clean.new_earnings AS ne
    WHERE
        ne.incentive_system = 'DEMAND_CONVERSION_FR'
        AND ne.status <> 'INVALIDATED'
    GROUP BY
        ne.id_earning_source
),
rent_flows AS (
    SELECT
        rf.id_current_contract AS id_contract,
        COUNT(DISTINCT arf.id_agent) AS agents_count
    FROM
        datalake_ebdb_clean.rent_flow AS rf
    INNER JOIN
        datalake_ebdb_clean.agent_rent_flow AS arf
            ON arf.id_rent_flow = rf.id
    GROUP BY
        rf.id_current_contract
),
result AS (
    SELECT DISTINCT
        es.id_external_domain AS id_contract,
        es.status,
        CASE
            WHEN ne.revenue_percentage IS NOT NULL
                THEN CONCAT(format_number(100 * COALESCE(ne.revenue_percentage, 0), 2), '%')
        END AS incentive_system_earning_percentage,
        CASE
            WHEN ret_c.brokerage_estate_agent_share IS NOT NULL
                THEN CONCAT(format_number(100 * (COALESCE(ret_c.brokerage_estate_agent_share, 0) / rf.agents_count), 2), '%')
        END AS seubarriga_percentage,
        es.dt_competence,
        es.ts_occurred AS ts_signed
    FROM
        datalake_big_agent_clean.earning_sources AS es
    LEFT JOIN
        new_earnings AS ne
            ON ne.id_earning_source = es.id
    LEFT JOIN
        datalake_retsuko_clean.contract AS ret_c
            ON CAST(ret_c.id_external AS STRING) = es.id_external_domain
    LEFT JOIN
        rent_flows AS rf
            ON CAST(rf.id_contract AS STRING) = es.id_external_domain
    WHERE
        es.external_domain_type = 'RENT_CONTRACT'
        AND es.status <> 'CANCELED'
        AND es.revenue_share_total_amount <> 0
        AND ROUND(COALESCE(ret_c.brokerage_estate_agent_share, 0) / rf.agents_count, 3)
            IS DISTINCT FROM ROUND(COALESCE(ne.revenue_percentage, 0) / rf.agents_count, 3)
        AND es.dt_competence >= TRUNC(CURRENT_DATE(), 'MM')
        AND es.ts_occurred < CAST(CURRENT_DATE() AS TIMESTAMP) - INTERVAL 1 SECOND
)
SELECT
    id_contract,
    status,
    incentive_system_earning_percentage,
    seubarriga_percentage,
    dt_competence,
    ts_signed,
    CURRENT_TIMESTAMP() AS ts_validated
FROM
    result
UNION ALL
SELECT
    '-1' AS id_contract,
    'NO_DIVERGENCE' AS status,
    NULL AS incentive_system_earning_percentage,
    NULL AS seubarriga_percentage,
    CURRENT_DATE() AS dt_competence,
    CURRENT_TIMESTAMP() AS ts_signed,
    CURRENT_TIMESTAMP() AS ts_validated
