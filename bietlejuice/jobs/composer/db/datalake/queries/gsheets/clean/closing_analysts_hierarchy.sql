SELECT
    name,
    CAST(employee_id AS INT) AS employee_id,
    group_1,
    group_2,
    group_3,
    employee_hiring_type,
    analyst_3,
    managers,
    email,
    name_in_monday,
    status,
    is_trust_employee,
    TO_DATE(dt_start, 'dd/MM/yyyy') AS dt_start,
    TO_DATE(dt_first_experience_period_end, 'dd/MM/yyyy') AS dt_first_experience_period_end,
    TO_DATE(dt_second_experience_period_end, 'dd/MM/yyyy') AS dt_second_experience_period_end,
    TO_DATE(dt_born, 'dd/MM/yyyy') AS dt_born
FROM
    datalake_gsheets_raw.closing_analysts_hierarchy