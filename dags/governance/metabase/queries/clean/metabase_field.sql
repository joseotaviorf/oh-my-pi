SELECT
    id,
    table_id AS id_table,
    parent_id AS id_parent,
    fk_target_field_id AS id_fk_target_field,
    name,
    display_name,
    description,
    base_type,
    special_type,
    position,
    has_field_values AS field_values,
    visibility_type,
    fingerprint,
    fingerprint_version,
    database_type AS database_field_type,
    settings,
    active AS is_active,
    preview_display AS has_preview_display,
    last_analyzed AS ts_last_analyzed,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_metabase_raw.metabase_field
WHERE
    MAKE_DATE(year, month, day) BETWEEN "{load_start_date}" AND "{load_end_date}"
