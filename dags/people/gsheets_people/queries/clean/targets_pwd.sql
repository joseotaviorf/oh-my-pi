SELECT
    fechamento AS closure,
    quarter,
    FLOAT(target_pwd) AS targer_pwd,
    ts_load
FROM datalake_gsheets_people_raw.targets_pwd