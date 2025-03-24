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
    datalake_terminator_test_raw.checklist_item
