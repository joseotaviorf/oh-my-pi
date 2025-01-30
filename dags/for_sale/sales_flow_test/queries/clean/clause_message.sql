SELECT
    id,
    subject_id AS id_subject,
    parent_id AS id_parent,
    description,
    payment_method,
    title,
    order_clause,
    variables,
    is_negotiation_clause,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(updated_at) AS ts_updated,
    year,
    month,
    day
FROM
   datalake_sales_flow_test_raw.clause_message