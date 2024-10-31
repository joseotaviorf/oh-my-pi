SELECT
    id_colaborador AS id_employee,
    id_gestor_antigo AS id_old_manager,
    id_gestor_novo AS id_new_manager,
    nome AS employee_name,
    matricula AS employee_registration,
    email AS employee_email,
    nome_gestor_antigo AS old_manager_name,
    nome_gestor_novo AS new_manager_name,
    tipo_alteracao AS change_type,
    data_alteracao AS dt_change,
    ts_load
FROM datalake_gsheets_people_raw.managers_history