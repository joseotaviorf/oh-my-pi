SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    label,
    label_mod AS mod_label,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.tag_aud
