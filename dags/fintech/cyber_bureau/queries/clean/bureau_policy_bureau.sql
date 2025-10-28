SELECT
    CD_POLITICA AS id_policy,
    DT_INI_VIG AS ts_validity_start,
    CD_BUREAU AS id_bureau,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_politica_mnr_bureau
