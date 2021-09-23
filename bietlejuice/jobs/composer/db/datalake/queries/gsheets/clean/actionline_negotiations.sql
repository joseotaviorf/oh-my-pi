SELECT
    CAST(id_ciq AS INT) AS id_partner,
    analista_responsavel AS attendant,
    NULLIF(resultado_da_ligacao, '') AS call_result,
    ciq_receptivo AS ciq_feedback,
    frente AS cluster,
    comentario as comments,
    prioridade_indicada AS current_pitch,
    pitch_passado AS last_pitch,
    enviou_macro_Qual AS macro_sent,
    identificou_algum_problema AS opportunity,
    TO_TIMESTAMP(NULLIF(ts_resposta,''),'MM/dd/yyyy HH:mm:ss') AS ts_input
FROM 
    datalake_gsheets_raw.tratativas_actionline
