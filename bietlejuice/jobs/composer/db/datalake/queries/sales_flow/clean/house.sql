SELECT
    id,
    external_id AS id_external,
    address_data_id AS id_address_data,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.house
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}