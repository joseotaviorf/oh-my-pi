SELECT
    id_colaborador AS id_employee,
    nome AS employee_name,
    matricula AS employee_registration,
    email AS employee_email,
    cargo_antigo AS old_position,
    cargo_novo AS new_position,
    tipo_alteracao AS change_type,
    make_date(split(data, '/')[2], split(data, '/')[0], split(data, '/')[1]) AS dt_change,
    ts_load AS ts_load
FROM datalake_gsheets_people_raw.position_history