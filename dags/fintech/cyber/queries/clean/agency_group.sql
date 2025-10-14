SELECT
    GAGRUPO AS agency_group,
    GAAGENCY AS id_agency,
    GAPERCREMUN AS percentage_remuneration,
    NOW() AS ts_load
FROM datalake_cyber_raw.tb_grupo_agency
