SELECT 
    id, 
    bairro_id AS id_neighborhood,
    nome AS unit_name, 
    slug AS unit_slug_name, 
    logradouro AS address, 
    numero AS unit_number, 
    complemento AS address_complement, 
    telefone_venda AS phone_for_sale, 
    telefone_aluguel AS phone_for_rent, 
    CAST(visivel AS BOOLEAN) AS is_visible, 
    CAST(criado_em AS TIMESTAMP) AS ts_created, 
    CAST(desativado_em AS TIMESTAMP) AS ts_disabled
FROM
    datalake_casa_mineira_crm_raw.unidade 