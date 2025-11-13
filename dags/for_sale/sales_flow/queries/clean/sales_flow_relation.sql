SELECT
    id,
    sales_flow_id AS id_sales_flow,
    related_id AS id_related,
    source_type,
    related_as,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_relation
