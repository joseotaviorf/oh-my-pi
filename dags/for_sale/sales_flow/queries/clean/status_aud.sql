SELECT
    id,
    label_id AS id_label,
    parent_id AS id_parent,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    key,
    label_id_mod AS mod_id_label,
    parent_id_mod AS mod_id_parent,
    key_mod AS mod_key,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.status_aud

