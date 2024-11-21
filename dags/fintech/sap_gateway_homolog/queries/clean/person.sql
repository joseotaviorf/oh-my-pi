SELECT
    id              AS id_person,
    tax_id          AS id_tax,
    tax_id_type     AS id_tax_type,
    `name`          AS person_name,
    email,
    phone,
    address,
    address_complement,
    address_street_sufix,
    address_number,
    address_block,
    city,
    state,
    zip_code,
    created_at      AS ts_created,
    updated_at      AS ts_updated
FROM
    datalake_sap_gateway_homolog_raw.person
