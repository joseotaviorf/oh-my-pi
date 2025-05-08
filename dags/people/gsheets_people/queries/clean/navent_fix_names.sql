SELECT 
    email AS employee_email,
    nome AS employee_name,
    banda AS employee_band,
    email_gestor AS manager_email,
    ts_load AS ts_load
FROM datalake_gsheets_people_raw.navent_fix_names