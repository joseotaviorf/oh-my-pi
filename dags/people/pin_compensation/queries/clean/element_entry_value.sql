SELECT
    element_entry_value_id AS id_element_entry_value,
    element_entry_id AS id_element_entry,
    input_value_id AS id_input_value,
    enterprise_id AS id_enterprise,
    screen_entry_value,
    created_by,
    last_updated_by AS updated_by,
    CAST(object_version_number AS INT) AS object_version_number,
    TO_DATE(effective_start_date) AS dt_effective_started,
    TO_DATE(effective_end_date) AS dt_effective_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_compensation_raw.pay_element_entry_values_f
