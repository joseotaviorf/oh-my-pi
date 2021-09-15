SELECT
    id,
    earning_id AS id_earning,
    external_id AS id_external,
    accrual_year_month,
    due_date,
    entries,
    purpose,
    external_created_at AS ts_created_external,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_big_agent_raw.external_invoice
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
