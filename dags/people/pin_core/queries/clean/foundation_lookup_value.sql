SELECT
    row_id AS id_row,
    set_id AS id_set,
    view_application_id AS id_view_application,
    lookup_code,
    lookup_type,
    source_lang AS source_language_code,
    language AS language_code,
    meaning,
    description,
    created_by,
    last_updated_by AS updated_by,
    change_since_last_refresh = 'Y' AS has_changed_since_last_refresh,
    enabled_flag = 'Y' AS is_enabled,
    TO_TIMESTAMP(start_date_active) AS ts_activity_started,
    TO_TIMESTAMP(end_date_active) AS ts_activity_ended,
    TO_TIMESTAMP(creation_date) AS ts_created,
    TO_TIMESTAMP(last_update_date) AS ts_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_pin_core_raw.fnd_lookup_values
