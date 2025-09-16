SELECT
    id,
    field_choice_id AS id_field_choice,
    field_value_id AS id_field_value,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load
FROM
    datalake_workable_redshift_raw.field_value_choices