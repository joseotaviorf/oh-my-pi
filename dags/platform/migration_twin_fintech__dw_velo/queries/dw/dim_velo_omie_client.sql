SELECT
    id_client AS sk_client,
    corporate_name,
    name_doing_business_as,
    client_cpf_cnpj,
    email,
    address,
    address_number,
    address_complement,
    neighborhood,
    city,
    state,
    country_code,
    is_natural_person,
    is_foreign,
    is_active,
    NOW() AS ts_load
FROM
    datalake_velo.omie_client
