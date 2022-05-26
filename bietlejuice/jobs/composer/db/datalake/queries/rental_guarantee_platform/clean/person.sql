SELECT
    id,
    address_id AS id_address,
    personuuid AS uuid_person,
    person_type,
    person_name,
    declared_income,
    contract_responsible AS is_contract_responsible,
    is_foreign,
    version,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.person
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
