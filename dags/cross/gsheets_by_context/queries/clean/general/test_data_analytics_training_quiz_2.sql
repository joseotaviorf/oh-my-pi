SELECT
    timestamp(date) as date,
    email,
    points,
    question_1,
    question_2,
    question_3,
    line,
    ts_load
FROM
    datalake_gsheets_raw.test_data_analytics_training_quiz_2
