SELECT
    account,
    supervisor,
    goal_name,
    CAST(goal_value AS FLOAT) AS goal_value,
    DATE(date) AS date,
    INT(month) AS month,
    INT(year) AS year
FROM
    datalake_gsheets_raw.ppmulti_goals_am