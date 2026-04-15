SELECT
    id AS id_note_aud,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    message,
    type,
    sales_flow_id_mod AS mod_id_sales_flow,
    message_mod AS mod_message,
    type_mod AS mod_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.note_aud
