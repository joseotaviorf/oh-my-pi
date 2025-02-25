SELECT
    id,
    sales_flow_id AS id_sales_flow,
    clause_message_id AS id_message_clause,
    variables,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.ccv_clause

