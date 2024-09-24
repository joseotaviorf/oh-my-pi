SELECT
    cod_dev AS id_debtor,
    cod_pes AS id_person,
    NOW() AS ts_load
FROM datalake_webhelp_raw.devedores
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_dev ORDER BY subfolder DESC) = 1
