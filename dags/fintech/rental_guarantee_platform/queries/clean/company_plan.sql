SELECT
    id,
    plan_id AS id_plan,
    company_id AS id_company,
    pricing,
    coverage,
    damage,
    commission,
    version,
    active AS is_active,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.company_plan
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
