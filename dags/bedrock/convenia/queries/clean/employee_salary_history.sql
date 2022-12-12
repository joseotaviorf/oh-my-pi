SELECT
    id,
    relationship_id AS id_relationship,
    department_id AS id_department,
    job_description_id AS id_job_description,
    cost_center_id AS id_cost_center,
    motive_id AS id_motive,
    salary,
    relationship,
    department,
    job,
    cost_center,
    motive,
    description,
    is_active,
    date_from AS dt_from,
    date_to AS dt_to,
    created_at AS dt_created,
    updated_at AS dt_updated
FROM
    datalake_convenia_raw.employee_salary_history