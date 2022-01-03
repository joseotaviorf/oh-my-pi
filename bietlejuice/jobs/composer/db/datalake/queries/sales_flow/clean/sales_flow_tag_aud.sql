SELECT
    id AS id_sales_flow_tag_aud,
    sales_flow_id AS id_sales_flow,
    tag_id AS id_tag,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.sales_flow_tag_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}