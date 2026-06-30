SELECT
    lr.uuid_lead_resolution AS sk_lead_resolution,
    lr.uuid_lead_session AS sk_lead_session,
    ls.uuid_lead AS sk_lead,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    lr.type,
    lr.property_id AS id_synthetic_house,
    lr.ts_sent_to_crm IS NOT NULL AS is_sent_to_crm,
    lr.ts_resolved,
    lr.ts_sent_to_crm,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(lr.ts_resolved) AS year,
    MONTH(lr.ts_resolved) AS month,
    DAY(lr.ts_resolved) AS day
FROM
    datalake_alias_clean.lead_resolutions AS lr
JOIN
    datalake_alias_clean.lead_sessions AS ls
        ON lr.uuid_lead_session = ls.uuid_lead_session
JOIN
    datalake_alias_clean.leads AS l
        ON ls.uuid_lead = l.uuid_lead
LEFT JOIN
    core_brokers.brokers AS cb
        ON l.uuid_company = cb.uuid_company