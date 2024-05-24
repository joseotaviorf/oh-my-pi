SELECT 
    id,
    termination_id AS id_termination,
    name AS checklist_item,
    active AS is_active,
    done AS is_done, 
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_terminator_raw.checklist_item
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
