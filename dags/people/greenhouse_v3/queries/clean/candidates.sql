SELECT
    -- ids
    id AS id_candidate,
    linked_user_ids[0] AS id_linked_user,
    -- text fields
    first_name,
    last_name,
    CONCAT(first_name, ' ', last_name) AS full_name,
    custom_fields.national_id.value AS national_document_number,
    custom_fields.nationality.value AS nationality,
    company AS current_company,
    title AS current_job_title,
    custom_fields.personal_number.value AS hired_person_number,
    custom_fields.nif.value AS hired_nif_tax_document_number,
    custom_fields.portugal_offer_passaporte.value AS hired_passport_number,
    custom_fields.pc_d_offer_acessibilidade_1__esp_.value AS hired_accessibility_need,
    custom_fields.pc_d_offer_acessibilidade_2__esp_.value AS hired_accessibility_hybrid_office_needs,
    custom_fields.pc_d_offer_acessibilidade_3__esp_.value AS hired_accessibility_funding_preference,
    custom_fields.employee_id.value AS pin_internal_person_number,
    custom_fields.current_job_title.value AS pin_internal_job_title,
    custom_fields.current_band.value AS pin_internal_band,
    -- numeric
    CAST(custom_fields.current_tenure.value AS INT) AS pin_internal_tenure,
    CAST(custom_fields.time_since_last_movement.value AS INT) AS pin_internal_months_since_last_move,
    CAST(custom_fields.current_salary.value AS DECIMAL(10,2)) AS salary_pin_internal,
    -- boolean
    CAST(private AS BOOLEAN) AS is_private,
    CAST(can_email AS BOOLEAN) AS has_valid_email,
    custom_fields.previous_employee.value = 'Yes' AS is_previous_employee,
    CAST(custom_fields.work_authorization.value AS BOOLEAN) AS has_work_authorization_hired,
    custom_fields.has_rvv.value = 'Yes' AS has_rvv_pin_internal,
    -- dates
    TO_DATE(custom_fields.birth_date_candidate_1752263668_438955.value, 'dd/MM/yyyy') AS dt_birthday_hired,
    -- timestamps
    CAST(created_at AS TIMESTAMP) AS ts_created,
    CAST(updated_at AS TIMESTAMP) AS ts_updated,
    NOW() AS ts_load,
    -- arrays
    tags,
    linked_user_ids,
    email_addresses,
    phone_numbers,
    social_media_addresses,
    website_addresses,
    addresses,
    custom_fields,
    -- partitions
    year,
    month,
    day
FROM
    datalake_greenhouse_v3_raw.candidates
