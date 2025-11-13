SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    json_label,
    json_label_mod AS mod_json_label,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.label_aud
