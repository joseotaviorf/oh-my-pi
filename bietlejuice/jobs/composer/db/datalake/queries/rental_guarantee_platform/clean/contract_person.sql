SELECT
    id,
    contract_id AS id_contract,
    person_id AS id_person,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.contract_person
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}