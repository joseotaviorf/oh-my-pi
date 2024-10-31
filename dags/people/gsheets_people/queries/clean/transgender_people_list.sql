SELECT
    nome_de_registro AS employee_registration_name,
    email AS employee_email,
    nome_social AS employee_social_name,
    alterar AS has_to_change,
    ts_load
FROM datalake_gsheets_people_raw.transgender_people_list