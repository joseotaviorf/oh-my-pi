SELECT
    NULLIF(codigo_contrato,'') AS id_contract,
    NULLIF(nome_iq,'') AS tenant_name,
    NULLIF(telefone_iq,'') AS tenant_phone,
    NULLIF(endereco,'') AS house_address,
    NULLIF(numero,'') AS house_number,
    NULLIF(complemento,'') AS house_complement,
    NULLIF(cep,'') AS house_zipcode,
    NULLIF(bairro,'') AS house_neighborhood,
    NULLIF(cidade,'') AS house_city,
    NULLIF(iq_ciente_entrada_imovel_somente_na_vigencia,'') AS tenant_aware_of_entrance_only_in_entrance_date,
    TO_TIMESTAMP(NULLIF(ts_resposta_forms,''),'M/d/y H:m:s') AS ts_answer_form
FROM
    datalake_gsheets_raw.keys_logistic_onboarding_tenant_b2b