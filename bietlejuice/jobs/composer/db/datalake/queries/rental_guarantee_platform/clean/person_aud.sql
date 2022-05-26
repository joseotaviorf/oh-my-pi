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
    rev,
    revend AS rev_end,
    revtype AS rev_type,
    address_id_mod AS mod_id_address,
    personuuid_mod AS mod_uuid_person,
    person_type_mod AS mod_person_type,
    contract_responsible_mod AS mod_is_contract_responsible,
    person_name_mod AS mod_person_name,
    declared_income_mod AS mod_declared_income,
    is_foreign_mod AS mod_is_foreign,
    created_at AS ts_created,
    year,
    month,
    day
FROM
    datalake_rental_guarantee_platform_raw.person_aud
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}