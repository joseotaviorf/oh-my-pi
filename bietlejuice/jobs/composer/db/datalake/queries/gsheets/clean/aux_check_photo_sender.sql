SELECT
    CAST(house_id AS BIGINT) AS id_house,
    job_id_fl AS id_photo_job,
    analisado_por AS analyzed_by,
    user_sender_final AS final_user_sender,
    classificacao_final AS final_classification,
    classificacao_motivo_final AS final_classification_reason,
    classificacao_comentarios_final AS final_classification_comments,
    tem_plaquinha AS sign_placement,
    CAST(analisado_em AS DATE) AS dt_analyzed
FROM
    datalake_gsheets_raw.aux_check_photo_sender