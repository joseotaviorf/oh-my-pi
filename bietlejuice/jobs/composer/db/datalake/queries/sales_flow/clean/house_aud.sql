SELECT
    id,
    external_id AS id_external,
    address_data_id AS id_address_data,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    external_id_mod AS mod_id_external,
    address_data_id_mod AS mod_id_address_data,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.house_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}