SELECT
    id_client,
    corporate_name,
    name_doing_business_as,
    client_cpf_cnpj,
    email,
    address,
    address_number,
    address_complement,
    address_neighborhood AS neighborhood,
    address_city AS city,
    address_state AS state,
    co.abbreviation AS country_code,
    is_natural_person,
    is_foreign,
    NOT is_inactive AS is_active
FROM
    datalake_velo_omie_clean.clients AS cl
LEFT JOIN
    datalake_velo_omie_clean.country AS co
    ON co.id_country = cl.address_country_code

