SELECT
    id,
    earning_id AS id_earning,
    external_id AS id_external,
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    accrual_year_month,
    entries,
    purpose,
    earning_id_mod AS mod_id_earning,
    external_id_mod AS mod_id_external,    
    accrual_year_month_mod AS mod_accrual_year_month,
    entries_mod AS mod_entries,
    purpose_mod AS mod_purpose,
    due_date_mod AS mod_dt_due,
    external_created_at_mod AS mod_ts_created_external,
    created_at_mod AS mod_ts_created,
    updated_at_mod AS mod_ts_updated,
    DATE(due_date) AS dt_due,
    external_created_at AS ts_created_external,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.external_invoice_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
