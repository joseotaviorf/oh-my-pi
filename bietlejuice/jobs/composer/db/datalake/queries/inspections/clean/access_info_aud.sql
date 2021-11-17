SELECT
    id,
    rev,
    revtype AS rev_type,
    location,
    phone,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_inspections_raw.access_info_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}