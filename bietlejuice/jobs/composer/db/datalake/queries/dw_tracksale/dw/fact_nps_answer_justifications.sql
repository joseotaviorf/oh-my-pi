SELECT
    id_answer AS sk_nps_answer,
    level,
    justification,
    current_timestamp AS ts_load
FROM 
    (SELECT * FROM datalake_tracksale.answer_justifications
    UNION ALL
    SELECT * FROM datalake_casa_mineira_tracksale.answer_justifications) -- we are merging historical data from Casa Mineira's Tracksale account