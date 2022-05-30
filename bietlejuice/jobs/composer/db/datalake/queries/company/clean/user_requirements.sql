SELECT
    id,
    company_id AS id_company,
    requirements,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.user_requirements
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
