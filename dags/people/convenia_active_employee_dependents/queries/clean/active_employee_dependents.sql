SELECT
    id,
    employee_id AS id_employee,
    relation_esocial_id AS id_relation_esocial,
    name,
    last_name,
    email,
    cpf,
    mother_name,
    dependent_relation,
    dependent_relation_description,
    description,
    phone,
    benefits,
    source,
    ir AS is_ir,
    foreigner AS is_foreigner,
    family_salary AS is_family_salary,
    birth_date AS dt_birth
FROM
    datalake_convenia_dependents_raw.active_employee_dependents
