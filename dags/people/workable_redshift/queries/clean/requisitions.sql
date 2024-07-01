SELECT
    -- ids
    id,
    -- non-ids
    requisition_template_id AS id_requisition_template,
    approval_workflow_id AS id_approval_workflow,
    department_id AS id_department,
    job_id AS id_job,
    candidate_id AS id_candidate,
    requester_id AS id_requester,
    owner_id As id_owner,
    hiring_manager_id AS id_hiring_manager,
    -- non-metrics
    country_code,
    state_code,
    city,
    subregion,
    zip_code,
    code,
    employment_type,
    experience,
    salary_currency,
    salary_frequency,
    offered_salary_currency,
    offered_salary_frequency,
    notes,
    state,
    reason,
    -- metrics
    salary_from,
    salary_to,
    offered_salary,
    -- booleans
    -- dates
    plan_date AS dt_plan,
    start_date AS dt_start,
    opened_on AS dt_opened,
    filled_on AS dt_filled,
    -- timestamps
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM datalake_workable_redshift_raw.requisitions
WHERE 
    DATE(updated_at) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')