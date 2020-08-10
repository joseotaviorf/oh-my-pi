SELECT
    id_answer AS sk_nps_answer,
    level,
    justification,
    current_timestamp AS ts_load
FROM datalake_tracksale.answer_justifications
