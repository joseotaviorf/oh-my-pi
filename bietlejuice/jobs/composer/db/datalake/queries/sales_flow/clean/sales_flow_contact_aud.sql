SELECT
    id AS id_sales_flow_contact,
    sales_flow_id AS id_sales_flow,
    contact_id AS id_contact,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    type,
    default_type AS is_default_type,
    sales_flow_id_mod AS mod_id_sales_flow,
    contact_id_mod AS mod_id_contact,
    type_mod AS mod_type,
    default_type_mod AS mod_is_default_type,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_contact_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}