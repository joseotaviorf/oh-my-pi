SELECT
    id_company AS sk_company,
    company_name,
    street,
    `number`,
    complement,
    neighborhood,
    city,
    state,
    country_code,
    zipcode,
    geolocation,
    cnpj,
    ts_created,
    ts_updated,
    NOW() AS ts_load
FROM
    datalake_velo.propose_company
