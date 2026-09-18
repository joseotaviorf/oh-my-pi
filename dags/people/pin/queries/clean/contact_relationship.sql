-- Effective-dated employee-to-contact relationships used to identify dependents.
SELECT
    contact_relationship_id AS id_contact_relationship,
    person_id AS id_person,
    contact_person_id AS id_contact_person,
    business_group_id AS id_business_group,
    legislation_code,
    contact_type,
    statutory_dependent,
    cont_attribute1 AS irrf_dependent_type_code,
    CAST(sequence_number AS INT) AS sequence_number,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    dependent_flag = 'Y' AS is_dependent,
    beneficiary_flag = 'Y' AS is_beneficiary,
    existing_person = 'Y' AS is_existing_person,
    bondholder_flag = 'Y' AS is_bondholder,
    personal_flag = 'Y' AS is_personal_relationship,
    primary_contact_flag = 'Y' AS is_primary_contact,
    rltd_per_rsds_w_dsgntr_flag = 'Y' AS is_related_person_residing_with_designator,
    third_party_pay_flag = 'Y' AS is_third_party_pay,
    emergency_contact_flag = 'Y' AS is_emergency_contact,
    TO_DATE(effective_start_date) AS dt_effective_started,
    COALESCE(
        NULLIF(TO_DATE(effective_end_date), DATE('4712-12-31')),
        DATE('9999-12-31')
    ) AS dt_effective_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_pin_core_raw.per_contact_relships_f
