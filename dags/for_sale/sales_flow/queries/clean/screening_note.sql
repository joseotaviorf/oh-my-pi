SELECT
    id,
    screening_id AS id_screening,
    note_id AS id_note,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.screening_note
