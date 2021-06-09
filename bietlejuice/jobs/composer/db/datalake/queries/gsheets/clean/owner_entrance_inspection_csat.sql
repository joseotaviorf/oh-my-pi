SELECT 
    INT(id_do_contrato) AS id_contract,
    NULLIF(email,'') AS email,
    NULLIF(pontos_de_melhoria,'') AS improvement_tags,
    NULLIF(campo_aberto,'') AS comments,
    INT(avaliacao_csat) AS general_satisfaction_evaluation,
    TIMESTAMP(submitted_at) AS ts_submitted
FROM 
    datalake_gsheets_raw.csat_vistoria_pp_entrada
