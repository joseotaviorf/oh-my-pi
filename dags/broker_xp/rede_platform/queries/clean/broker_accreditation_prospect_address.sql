SELECT
    id,
    prospect_id AS id_prospect,
    postal_code,
    street,
    number AS street_number,
    complement,
    neighborhood,
    state,
    city,
    year,
    month,
    day
FROM
    datalake_rede_platform_raw.broker_accreditation_prospect_address
