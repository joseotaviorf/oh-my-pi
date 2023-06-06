SELECT
    to_timestamp(date, "dd/MM/yyyy HH:mm:ss") AS answer_date,
    email,
    points,
    line,
    question_1,
    ts_load
FROM
    datalake_gsheets_raw.data_analytics_training_06_sql_intermediate
