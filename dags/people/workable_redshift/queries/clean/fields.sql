SELECT
    id,
    owner_id AS id_owner,
    "type",
    label,
    hint,
    preview_value,
    owner_type,
    single_answer AS is_single_answer,
    created_at AS ts_created,
    updated_at AS ts_updated,
    NOW() AS ts_load 
FROM
    datalake_workable_redshift_raw.fields
WHERE  
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')