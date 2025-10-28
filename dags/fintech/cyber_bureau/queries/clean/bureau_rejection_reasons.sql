SELECT
    CD_MOTIVO AS reason_code,
    DS_MOTIVO AS reason_description,
    CD_BUREAU AS id_bureau,
    NOW() AS ts_load
FROM datalake_cyber_bureau_raw.tb_motivos_rejeicoes_mnr
