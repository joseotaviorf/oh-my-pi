SELECT
    id AS id_charge_delay,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    waiting_period,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM 
    datalake_owner_fees_raw.charge_delay_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
