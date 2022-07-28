SELECT
    id,
    company_id AS id_company,
    draft,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_draft
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}