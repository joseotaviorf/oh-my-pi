SELECT
    id,
    sales_flow_id AS id_sales_flow,
    firestore_id AS id_firestore,
    status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.offer
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}