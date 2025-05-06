SELECT
    business_group_id AS id_business_group,
    person_id AS id_person,
    mailing_address_id AS id_mailing_address,
    primary_email_id AS id_primary_email,
    primary_phone_id AS id_primary_phone,
    primary_nid_id AS id_primary_nid,
    person_number,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_DATE(start_date) AS dt_started,
    TO_DATE(effective_start_date) AS dt_effective_started,
    TO_DATE(effective_end_date) AS dt_effective_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.per_all_people_f
