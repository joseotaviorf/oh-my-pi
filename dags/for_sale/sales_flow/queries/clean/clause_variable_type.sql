SELECT
    id,
    input_type,
    element,
    options,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.clause_variable_type
