SELECT
    id,
    userinsert AS id_user_insert,
    userupdate AS id_user_update,
    type AS id_business_type,
    name,
    `percent`,
    coverage,
    damage,
    commission,
    active AS is_active,
    dateinsert AS ts_inserted,
    dateupdate AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.plans
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
