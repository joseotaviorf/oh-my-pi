SELECT
    to_timestamp(date, "dd/MM/yyyy HH:mm:ss") AS answer_date,
    email,
    points,
    line,
    question_1,
    question_2,
    ts_load
FROM
    datalake_gsheets_raw.data_analytics_training_02_life_cycle_analysis
         