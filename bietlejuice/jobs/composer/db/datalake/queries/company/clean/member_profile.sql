SELECT
    id,
    profile_id AS id_profile,
    person_uuid AS uuid_person,
    product_id AS id_product,
    status,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_company_raw.member_profile
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
