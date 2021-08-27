SELECT
    STRING(NULLIF(id_question,'')) AS id_question,
    STRING(NULLIF(full_question,'')) AS full_question
FROM
    datalake_gsheets_raw.ipsos_brandtracking_questions