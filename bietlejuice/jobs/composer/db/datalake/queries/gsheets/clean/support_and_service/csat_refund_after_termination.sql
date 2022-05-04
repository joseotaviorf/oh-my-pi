SELECT
    experiencia_reembolso AS customer_experience_feedback,
    sugestao_melhorias AS improvement_suggestions,
    CAST(nivel_satisfacao AS INTEGER) AS satisfation_level,
    TO_TIMESTAMP(timestamp, 'dd/MM/yyyy HH:mm:ss') AS ts_submitted
FROM
    datalake_gsheets_raw.csat_reembolso_pos_rescisao