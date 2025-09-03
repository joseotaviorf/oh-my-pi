SELECT
    -- ids
    id,
    recruiter.id AS id_recruiter,
    coordinator.id AS id_coordinator,
    custom_fields.employee_id AS id_employee,
    -- text fields
    custom_fields.national_id AS document_number,
    custom_fields.personal_number,
    first_name,
    last_name,
    company,
    title AS job_title,
    recruiter.name AS recruiter_name,
    coordinator.name AS coordinator_name,
    custom_fields.current_band,
    custom_fields.current_job_title,
    custom_fields.nome_completo AS full_name,
    -- boolean
    CAST(is_private AS BOOLEAN) AS is_private,
    CAST(can_email AS BOOLEAN) AS has_email_permission,
    custom_fields.previous_employee AS is_previous_employee,
    custom_fields.has_rvv,
    -- numeric
    custom_fields.current_salary,
    -- timestamps
    TO_DATE(custom_fields.birth_date, 'dd/MM/yyyy') AS dt_birthday,
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    CAST(last_activity AS TIMESTAMP) AS ts_last_activity,
    NOW() AS ts_load,
    -- arrays
    tags,
    application_ids,
    phone_numbers,
    addresses,
    email_addresses,
    website_addresses,
    social_media_addresses,
    attachments,
    TRANSFORM(
        educations,
        edu -> STRUCT(
            edu.id,
            edu.school_name,
            edu.degree,
            edu.start_date,
            edu.end_date
        )
    ) AS educations,
    employments,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.candidates
WHERE
    DATE(last_activity) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')