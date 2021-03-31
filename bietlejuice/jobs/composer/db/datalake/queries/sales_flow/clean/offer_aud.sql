SELECT
    id,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    firestore_id AS id_firestore,
    status,
    sales_flow_id_mod AS mod_id_sales_flow,
    firestore_id_mod AS mod_id_firestore,
    status_mod AS mod_status,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.offer_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}