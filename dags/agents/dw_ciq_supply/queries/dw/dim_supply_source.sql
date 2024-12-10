SELECT DISTINCT
    sk_supply_source,
    supply_source,
    NOW() AS ts_load
FROM
    datalake_ciq.ciq_supply_events_tracking
WHERE
    supply_source IS NOT NULL
