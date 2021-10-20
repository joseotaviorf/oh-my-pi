SELECT
    id AS id_brokerage_aud,
    sales_flow_id AS id_sales_flow,
    quinto_andar_brokerage_split,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    sales_flow_id_mod AS mod_id_sales_flow,
    quinto_andar_brokerage_split_mod AS mod_quinto_andar_brokerage_split,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.brokerage_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}