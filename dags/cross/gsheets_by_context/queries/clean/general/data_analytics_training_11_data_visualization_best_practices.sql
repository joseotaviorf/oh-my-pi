SELECT
    email,
    points,
    line,
    question_1,
    question_2,
    TO_TIMESTAMP(date, "dd/MM/yyyy HH:mm:ss") AS ts_answered,
    ts_load
FROM
    datalake_gsheets_raw.data_analytics_training_11_data_visualization_best_practices
