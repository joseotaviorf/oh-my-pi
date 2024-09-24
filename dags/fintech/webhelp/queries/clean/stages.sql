SELECT
    cod_est AS id_occurrence_stage,
    nom_est As name_occurrence_stage,
    NOW() AS ts_load
FROM datalake_webhelp_raw.estagios
QUALIFY ROW_NUMBER() OVER(PARTITION BY cod_est ORDER BY subfolder DESC) = 1
