SELECT
    cod_est AS id_occurrence_stage,
    nom_est As name_occurrence_stage,
    NOW() AS ts_load
FROM datalake_webhelp_raw.estagios
