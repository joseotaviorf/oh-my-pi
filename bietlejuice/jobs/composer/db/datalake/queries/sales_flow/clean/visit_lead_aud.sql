SELECT
    id,
    rev,
    revtype as rev_type,
    revend as rev_end,
    data,
    data_mod as mod_data,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.visit_lead_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}