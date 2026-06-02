WITH member_profile AS (
    SELECT
        mp.id_main_user,
        mp.uuid_company,
        mp.profile,
        mp.business_context,
        ROW_NUMBER() OVER(PARTITION BY mp.id_main_user ORDER BY mp.ts_relationship_ended DESC, mp.ts_relationship_started DESC) = 1 AS is_last_updated
    FROM
        datalake_hub_services.member_profile  AS mp
    WHERE
        mp.id_main_user IS NOT NULL
        AND mp.profile = 'AGENT'
),
big_agent_revenue_share AS (
    SELECT
        a.id_user,
        COALESCE(h.id_external, c.id_house) AS id_house,
        e.id_revenue_share,
        e.uuid_person,
        e.incentive_system,
        mp.business_context,
        e.revenue_amount,
        e.revenue_percentage,
        DATE(e.ts_updated) AS dt_updated,
        e.ts_created
    FROM
        datalake_big_agent.earnings AS e
    LEFT JOIN
        datalake_agent_accreditation.agent AS a
            ON e.uuid_person = a.uuid_person
    LEFT JOIN
        datalake_sales_flow_clean.sales_flow AS sf
            ON sf.id = e.id_sales_flow
    LEFT JOIN
        datalake_sales_flow_clean.house AS h
            ON h.id = sf.id_house
    LEFT JOIN
        datalake_ebdb_clean.contract AS c 
            ON c.id = e.id_contract
    LEFT JOIN
        member_profile AS mp
            ON mp.id_main_user = a.id_user
            AND mp.is_last_updated = TRUE
    WHERE
        e.id_revenue_share IS NOT NULL
        AND e.earning_status = 'CALCULATED'
        AND DATE(e.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
nazare_revenue_share AS (
    SELECT
        a.id_external AS id_user,
        rs.id_house,
        a.uuid_external_person AS uuid_person,
        rs.participant_role,
        mp.business_context,
        COALESCE(ROUND(CAST(GET_JSON_OBJECT(json_output, '$.gross-remuneration') AS DOUBLE), 2), 0) AS revenue_amount,
        COALESCE(ROUND(CAST(GET_JSON_OBJECT(json_output, '$.quintoandar-model-partner-brokerage-fee') AS DOUBLE), 2), 0) AS revenue_percentage,
        COALESCE(ROUND(CAST(GET_JSON_OBJECT(json_output, '$.tqc-bonus') AS DOUBLE), 2), 0) AS tqc_bonus,
        COALESCE(ROUND(CAST(GET_JSON_OBJECT(json_output, '$.remuneration-baseline') AS DOUBLE), 2), 0) AS remuneration_baseline,
        DATE(GREATEST(rs.ts_created, rs.ts_database_transaction)) AS dt_updated,
        rs.ts_created
    FROM
        datalake_nazare_clean.revenue_share_by_participant AS rs
    LEFT JOIN 
        datalake_nazare_clean.offer_agent AS oa
            ON oa.id_offer_agent = rs.id_offer_agent
    LEFT JOIN
        datalake_nazare_clean.agent AS a
            ON a.id_agent = oa.id_agent
    LEFT JOIN
        member_profile AS mp
            ON mp.id_main_user = a.id_external
            AND mp.is_last_updated = TRUE
    WHERE
        rs.ts_invalidated IS NULL
        AND DATE(GREATEST(rs.ts_created, rs.ts_database_transaction)) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
union_revenue_share AS (
    SELECT
        rs.id_user,
        rs.id_house,
        rs.uuid_person,
        rs.business_context,
        'BIG_AGENT' AS revenue_source,
        'DEMAND' AS revenue_role,
        SUM(rs.revenue_amount) AS revenue_amount,
        SUM(rs.revenue_percentage) AS revenue_percentage,
        MAX(rs.revenue_percentage) FILTER(WHERE rs.incentive_system = 'DEMAND_CONVERSION_FS') AS brokerage_percentage,
        MAX(rs.revenue_percentage) FILTER(WHERE rs.incentive_system = 'DEMAND_ACQUISITION_FS') AS tqc_percentage,
        NULL AS ciq_percentage,
        MAX(rs.revenue_percentage) FILTER(WHERE rs.incentive_system = 'DEMAND_ACQUISITION_FS') IS NOT NULL AS has_tqc_revenue_share,
        DATE(MAX(rs.ts_created)) AS dt_created,
        MAX(rs.dt_updated) AS dt_updated
    FROM
        big_agent_revenue_share AS rs
    WHERE
        rs.incentive_system IN ('DEMAND_CONVERSION_FS', 'DEMAND_ACQUISITION_FS')
    GROUP BY
        rs.id_user,
        rs.id_house,
        rs.uuid_person,
        rs.business_context
    UNION ALL
    SELECT
        rs.id_user,
        rs.id_house,
        rs.uuid_person,
        rs.business_context,
        'BIG_AGENT' AS revenue_source,
        'SUPPLY' AS revenue_role,
        rs.revenue_amount AS revenue_amount,
        rs.revenue_percentage AS revenue_percentage,
        NULL AS brokerage_percentage,
        NULL AS tqc_percentage,
        rs.revenue_percentage AS ciq_percentage,
        FALSE AS has_tqc_revenue_share,
        DATE(MAX(rs.ts_created)) AS dt_created,
        MAX(rs.dt_updated) AS dt_updated
    FROM
        big_agent_revenue_share AS rs
    WHERE
        rs.incentive_system IN ('SUPPLY_ACQUISITION_FS')
    GROUP BY
        rs.id_user,
        rs.id_house,
        rs.uuid_person,
        rs.business_context,
        rs.revenue_amount,
        rs.revenue_percentage
    UNION ALL
    SELECT
        rs.id_user,
        rs.id_house,
        rs.uuid_person,
        rs.business_context,
        'NAZARE' AS revenue_source,
        IF(rs.participant_role = 'CIQ', 'SUPPLY', 'DEMAND') AS revenue_role,
        rs.revenue_amount,
        rs.revenue_percentage,
        IF(rs.participant_role = 'CIQ', NULL, rs.remuneration_baseline) AS brokerage_percentage,
        IF(rs.tqc_bonus <> 0, rs.tqc_bonus, NULL) AS tqc_percentage,
        IF(rs.participant_role = 'CIQ', rs.revenue_percentage, NULL) AS ciq_percentage,
        rs.tqc_bonus <> 0 AS has_tqc_revenue_share,
        DATE(rs.ts_created) AS dt_created,
        rs.dt_updated
    FROM 
        nazare_revenue_share AS rs
)
SELECT
    rs.id_user,
    rs.id_house,
    rs.uuid_person,
    rs.business_context,
    rs.revenue_source,
    rs.revenue_role,
    rs.revenue_amount,
    rs.revenue_percentage,
    rs.brokerage_percentage,
    rs.tqc_percentage,
    rs.ciq_percentage,
    rs.has_tqc_revenue_share,
    rs.dt_created,
    rs.dt_updated,
    YEAR(rs.dt_updated) AS year,
    MONTH(rs.dt_updated) AS month,
    DAY(rs.dt_updated) AS day
FROM
    union_revenue_share AS rs