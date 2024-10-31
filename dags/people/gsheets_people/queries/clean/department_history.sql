SELECT
    id_colaborador AS id_employee,
    nome AS employee_name,
    matricula AS employee_registration,
    email AS employee_email,
    departamento_antigo AS old_department,
    departamento_novo AS new_department,
    tipo_alteracao AS change_type,
    make_date(split(data_alteracao, '/')[2], split(data_alteracao, '/')[0], split(data_alteracao, '/')[1]) AS dt_change,
    ts_load
FROM datalake_gsheets_people_raw.department_history