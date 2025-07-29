SELECT
    fsk.sk_file,
    f.id AS id_file,
    f.hash,
    f.file_name,
    f.type,
    f.url,
    f.has_3p_access_control,
    f.ts_created,
    f.ts_updated,
    NOW() AS ts_load
FROM
    datalake_brokers_supply_processor.file AS f
JOIN
    datalake_rede_supply.file_sks AS fsk
        ON f.id = fsk.id_file