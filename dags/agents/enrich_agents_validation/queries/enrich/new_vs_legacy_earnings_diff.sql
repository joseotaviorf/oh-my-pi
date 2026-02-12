SELECT
    COALESCE(es.id_external_domain, e.id_external_domain) AS id_contract,
    e.id AS id_legacy_earning,
    ne.id AS id_new_earning,
    es.external_domain_type,
    es.status,
    ne.revenue_percentage AS new_revenue_percentage,
    e.remuneration_value AS legacy_revenue_percentage,
    CASE
        WHEN erl.id IS NOT NULL THEN TRUE
        ELSE FALSE
    END AS has_legacy_percentage_manual_change,
    es.ts_created,
    e.ts_created AS ts_legacy_created,
    erl.ts_created AS ts_legacy_percentage_manual_changed
FROM
    datalake_big_agent_clean.earning_sources AS es
FULL OUTER JOIN
    datalake_big_agent_clean.new_earnings AS ne
        ON ne.id_earning_source = es.id
        AND ne.incentive_system = 'SUPPLY_ACQUISITION_FR'
        AND ne.status != 'INVALIDATED'
FULL OUTER JOIN
    datalake_big_agent_clean.earnings AS e
        ON e.id_external_domain = es.id_external_domain
        AND e.external_domain_type = 'RENT_CONTRACT'
        AND e.external_receiver_type = 'AGENT'
LEFT JOIN
    datalake_big_agent_clean.earning_remuneration_log AS erl
        ON erl.id_earning = e.id
WHERE
    (es.external_domain_type = 'RENT_CONTRACT' OR es.id IS NULL)
    AND (
        ne.revenue_percentage != e.remuneration_value
        OR ne.id IS NULL
        OR e.id IS NULL
    )
    AND e.ts_created >= DATE '2026-02-01'
UNION ALL
SELECT
    -1 AS id_contract,
    -1 AS id_legacy_earning,
    -1 AS id_new_earning,
    NULL AS external_domain_type,
    NULL AS status,
    NULL AS new_revenue_percentage,
    NULL AS legacy_revenue_percentage,
    NULL AS has_legacy_percentage_manual_change,
    NULL AS ts_created,
    NULL AS ts_legacy_created,
    NULL AS ts_legacy_percentage_manual_changed