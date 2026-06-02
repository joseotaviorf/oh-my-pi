WITH brokerage_share_history AS (
    SELECT
        ne.rev AS id_revision,
        es.id_external_domain AS id_contract,
        ROUND(SUM(ne.revenue_percentage), 2) AS agent_brokerage_share,
        FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)) AS ts_revision
    FROM
        datalake_big_agent_clean.earning_sources AS es
    JOIN
        datalake_big_agent_clean.new_earnings_aud AS ne
            ON es.id = ne.id_earning_source
    JOIN
        datalake_big_agent_clean.user_revision_entity AS ur
            ON ur.id = ne.rev
    WHERE
        es.external_domain_type = 'RENT_CONTRACT'
        AND ne.incentive_system = 'DEMAND_CONVERSION_FR'
        AND ne.status = 'CALCULATED'
        AND ne.revenue_percentage IS NOT NULL
        AND DATE(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0))) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    GROUP BY ne.rev, es.id_external_domain, ur.ts_revision
    UNION ALL
    SELECT
        ca.rev AS id_revision,
        ca.id_contract,
        ROUND(ca.agent_brokerage_share, 2) AS agent_brokerage_share,
        FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0)) AS ts_revision
    FROM 
        datalake_ebdb_clean.contract_aud AS ca
    JOIN 
        datalake_ebdb_clean.user_revision_entity AS ur
            ON ca.rev = ur.id
    LEFT JOIN
        datalake_big_agent_clean.earning_sources AS es
            ON ca.id_contract = es.id_external_domain
            AND es.external_domain_type = 'RENT_CONTRACT'
    WHERE
        es.id_external_domain IS NULL
        AND ca.agent_brokerage_share IS NOT NULL
        AND DATE(FROM_UNIXTIME(ROUND(ur.ts_revision / 1000.0))) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    bsh.id_revision,
    bsh.id_contract,
    bsh.agent_brokerage_share,
    bsh.ts_revision,
    DATE(bsh.ts_revision) AS dt_load,
    YEAR(bsh.ts_revision) AS year,
    MONTH(bsh.ts_revision) AS month,
    DAY(bsh.ts_revision) AS day
FROM 
    brokerage_share_history AS bsh