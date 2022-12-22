SELECT
    id_company AS sk_company,
    company_name,
    city,
    state,
    country,
    zipcode,
    geolocation,
    cnpj,
    NOW() AS ts_load
FROM
    datalake_velo.propose_company
