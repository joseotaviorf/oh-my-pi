SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    sales_flow_id AS id_sales_flow,
    sales_flow_id_mod AS mod_id_sales_flow,
    message,
    message_mod AS mod_message,
    type,
    type_mod AS mod_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.note_aud
