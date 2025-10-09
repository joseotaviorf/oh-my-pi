SELECT
    -- id
    id,
    linked_user_ids[0] AS id_linked_user,
    -- text
    first_name,
    last_name,
    CONCAT(first_name, ' ',  last_name) AS full_name,
    keyed_custom_fields.national_id.value AS national_document_number,
    keyed_custom_fields.nationality.value AS nationality,
    company AS current_company,
    title AS current_job_title,
    keyed_custom_fields.personal_number.value AS hired_person_number,
    keyed_custom_fields.nif AS hired_nif_tax_document_number,
    keyed_custom_fields.portugal_offer_passaporte AS hired_passport_number,
    keyed_custom_fields.pc_d_offer_acessibilidade_1__esp_ AS hired_accessibility_need,
    keyed_custom_fields.pc_d_offer_acessibilidade_2__esp_ AS hired_accessibility_hybrid_office_needs,
    keyed_custom_fields.pc_d_offer_acessibilidade_3__esp_ AS hired_accessibility_funding_preference,
    keyed_custom_fields.employee_id.value AS pin_internal_person_number,
    keyed_custom_fields.current_job_title.value AS pin_internal_job_title,
    keyed_custom_fields.current_band.value AS pin_internal_band,
    -- boolean
    is_private,
    can_email AS has_valid_email,
    keyed_custom_fields.previous_employee.value = 'Yes' AS is_previous_employee,
    keyed_custom_fields.work_authorization = 'Yes' AS has_work_authorization_hired,
    keyed_custom_fields.has_rvv.value = 'Yes' AS has_rvv_pin_internal,
    -- numeric
    CAST(keyed_custom_fields.current_tenure.value AS INT) AS pin_internal_tenure,
    CAST(keyed_custom_fields.time_since_last_movement.value AS INT) AS pin_internal_months_since_last_move,
    CAST(keyed_custom_fields.current_salary.value AS DECIMAL(10,2)) AS salary_pin_internal,
    -- date
    TO_DATE(keyed_custom_fields.birth_date_candidate_1752263668_438955.value, 'dd/MM/yyyy') AS dt_birthday_hired,
    -- timestamp
    created_at AS ts_created,
    updated_at AS ts_updated,
    last_activity AS ts_last_activity,
    ts_load, 
    -- array
    tags,
    application_ids,
    linked_user_ids,
    email_addresses,
    phone_numbers,
    social_media_addresses,
    website_addresses,
    educations,
    employments,
    addresses,
    keyed_custom_fields,
    -- partition
    year,
    month,
    day
FROM
    datalake_greenhouse_raw.candidates