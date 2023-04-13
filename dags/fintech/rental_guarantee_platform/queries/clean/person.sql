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

QUALIFY
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) = 1
