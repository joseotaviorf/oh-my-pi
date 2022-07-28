SELECT
    id AS id_rescission_aud,
    sales_flow_id AS id_sales_flow,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    reason,
    comment,
    sales_flow_id_mod AS mod_id_sales_flow,
    reason_mod AS mod_reason,
    comment_mod AS mod_comment,
    rescission_date_mod AS mod_dt_rescission,
    rescission_date AS dt_rescission,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.rescission_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}