SELECT
    aci.uuid_crm_integration AS sk_crm_integration,
    COALESCE(cb.sk_broker, -1) AS sk_broker,
    aci.platform,
    aci.is_active,
    aci.ts_created,
    aci.ts_updated,
    CURRENT_TIMESTAMP() AS ts_load,
    YEAR(aci.ts_updated) AS year,
    MONTH(aci.ts_updated) AS month,
    DAY(aci.ts_updated) AS day
FROM
    datalake_alias_clean.crm_integrations AS aci
LEFT JOIN
    core_brokers.brokers AS cb
        ON aci.uuid_company = cb.uuid_company