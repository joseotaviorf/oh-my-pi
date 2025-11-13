SELECT
    id,
    incremental_id as id_incremental,
    destination,
    headers,
    payload,
    published,
    message_partition,
    creation_time,
    creation_datetime,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.message
