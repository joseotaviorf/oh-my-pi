SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    screening_id AS id_screening,
    screening_id_mod AS mod_id_screening,
    note_id AS id_note,
    note_id_mod AS mod_id_note,
    status,
    status_mod AS mod_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.screening_note_aud
