SELECT
    id,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    sales_flow_id AS id_sales_flow,
    sales_flow_id_mod AS mod_id_sales_flow,
    related_id AS id_related,
    related_id_mod AS mod_id_related,
    source_type,
    source_type_mod AS mod_source_type,
    related_as,
    related_as_mod AS mod_related_as,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_relation_aud
