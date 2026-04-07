SELECT
    rev,
    TRUE AS has_3p_access_control,
    TO_TIMESTAMP(revtstmp/1000) AS ts_created,
    year,
    month,
    day
FROM
    datalake_brokers_supply_processor_raw.revinfo