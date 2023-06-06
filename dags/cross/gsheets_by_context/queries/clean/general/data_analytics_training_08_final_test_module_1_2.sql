SELECT
    to_timestamp(date, "dd/MM/yyyy HH:mm:ss") AS answer_date,
    email,
    points,
    line,
    question_1,
    question_2,
    question_3,
    question_4,
    question_5,
    question_6,
    question_7,
    question_8,
    question_9,
    question_10,
    ts_load
FROM
    datalake_gsheets_raw.data_analytics_training_08_final_test_module_1_2
