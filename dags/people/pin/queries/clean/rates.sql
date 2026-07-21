SELECT
    rate_id AS id_rate,
    business_group_id AS id_business_group,
    legislative_data_group_id AS id_legislative_data_group,
    action_occurrence_id AS id_action_occurrence,
    grade_ladder_id AS id_grade_ladder,
    legislation_code,
    currency_code,
    created_by,
    last_updated_by AS updated_by,
    rate_type,
    rate_object_type,
    rate_uom AS rate_unity_of_measure,
    rate_frequency,
    annualization_factor,
    INT(object_version_number) AS object_version_number,
    IF(progression_rate_flag = 'Y', TRUE, FALSE) AS is_progression_rate,
    IF(active_status = 'A', TRUE, FALSE) AS is_active,
    TO_DATE(effective_start_date) AS dt_effective_started,
    COALESCE(
        NULLIF(TO_DATE(effective_end_date), DATE('4712-12-31')),
        DATE('9999-12-31')
    ) AS dt_effective_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.per_rates_f