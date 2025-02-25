SELECT
    id,
    sales_flow_id as id_sales_flow,
    rev,
    revtype as rev_type,
    revend as rev_end,
    pendency,
    type,
    sales_flow_id_mod as mod_id_sales_flow,
    type_mod as mod_type,
    pendency_mod as mod_pendency,
    created_at as ts_created,
    updated_at as ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_pendency_aud

