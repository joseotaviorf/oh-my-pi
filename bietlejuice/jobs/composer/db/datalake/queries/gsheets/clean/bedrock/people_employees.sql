SELECT
    email,
    cargo AS role_name,
    departamento AS department_name,
    TO_DATE(dt_inicio, 'dd/MM/yyyy') AS dt_admission,
    TO_DATE(dt_desligamento, 'dd/MM/yyyy') AS dt_resignation
FROM
    datalake_gsheets_raw.people_data