SELECT
    id AS id_sales_flow_contact,
    sales_flow_id AS id_sales_flow,
    contact_id AS id_contact,
    type,
    default_type AS is_default_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_contact
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}