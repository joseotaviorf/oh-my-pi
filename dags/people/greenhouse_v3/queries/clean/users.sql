SELECT
    -- ids
    id,
    -- Non-ids (foreign keys)
    agency_id AS id_agency,
    employee_id AS id_employee,
    -- Non-metrics (properties)
    first_name,
    last_name,
    name,
    primary_email,
    job_title,
    -- Metrics (booleans)
    CAST(deactivated AS BOOLEAN) AS is_deactivated,
    CAST(site_admin AS BOOLEAN) AS is_site_admin,
    -- Date, timestamp
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- Partitions
    year,
    month,
    day,
    -- Arrays
    linked_candidate_ids,
    office_ids,
    department_ids,
    interviewer_tags,
    custom_fields
FROM
    datalake_greenhouse_v3_raw.users

