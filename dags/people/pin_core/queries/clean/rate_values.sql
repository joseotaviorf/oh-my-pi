SELECT
    rate_value_id AS id_rate_value,
    business_group_id AS id_business_group,
    action_occurrence_id AS id_action_occurrence,
    rate_id AS id_rate,
    rate_object_id AS id_rate_object,
    legislation_code,
    created_by,
    last_updated_by AS updated_by,
    rate_object_type,
    CAST(minimum AS FLOAT) AS minimum_value,
    CAST(mid_value AS FLOAT) AS mid_value,
    CAST(maximum AS FLOAT) AS maximum_value,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    TO_DATE(effective_start_date) AS dt_effective_started,
    TO_DATE(effective_end_date) AS dt_effective_ended,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.per_rate_values_f