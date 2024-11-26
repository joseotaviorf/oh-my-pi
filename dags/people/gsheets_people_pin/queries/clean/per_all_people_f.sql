SELECT
    person_id AS id_person,
    business_group_id AS id_business_group,
    primary_email_id AS id_primary_email,
    primary_phone_id AS id_primary_phone,
    mailing_address_id AS id_mailing_address,
    primary_nid_id AS id_primary_nid,
    person_number,
    applicant_number,
    created_by,
    last_updated_by AS updated_by,
    object_version_number,
    waive_data_protect AS is_data_protection_waived,
    creation_date AS dt_created,
    last_update_date AS dt_last_updated,
    start_date AS dt_started,
    effective_start_date AS dt_effective_start,
    effective_end_date AS dt_effective_end,
    NOW () AS ts_load
FROM
    datalake_gsheets_people_raw.per_all_people_f
