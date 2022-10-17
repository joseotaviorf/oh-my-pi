SELECT
    fsk.sk_file,
    f.id AS id_file,
    hash,
    file_name,
    type,
    url,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM
    datalake_brokers_supply_processor.file AS f
JOIN
    datalake_rede_supply.file_sks AS fsk
        ON f.id = fsk.id_file
