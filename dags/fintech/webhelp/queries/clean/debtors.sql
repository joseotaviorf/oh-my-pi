SELECT
    cod_dev AS id_debtor,
    cod_pes AS id_person,
    NOW() AS ts_load
FROM datalake_webhelp_raw.devedores
