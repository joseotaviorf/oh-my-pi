SELECT
    id                          AS id_address,
    ibge_code,
    zip_code,
    `address`                   AS address_description,
    `block`                     AS address_block,
    city                        AS address_city,
    complement                  AS address_complement,
    country                     AS address_country,
    `state`                     AS address_state,
    street_suffix,
    `number`                    AS address_number
FROM
    datalake_sap_gateway_homolog_raw.address
