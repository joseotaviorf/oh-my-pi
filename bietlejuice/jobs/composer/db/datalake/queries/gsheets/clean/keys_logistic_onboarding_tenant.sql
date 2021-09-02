SELECT
    NULLIF(codigo_contrato,'') AS id_contract,
    NULLIF(nome_iq,'') AS tenant_name,
    NULLIF(telefone_iq,'') AS tenant_phone,
    NULLIF(endereco,'') AS house_address,
    NULLIF(numero,'') AS house_number,
    NULLIF(cep,'') AS house_zipcode,
    NULLIF(bairro,'') AS house_neighborhood,
    NULLIF(cidade_de_entrega,'') AS house_city,
    NULLIF(complemento,'') AS house_complement,
    NULLIF(observacao,'') AS comments,
    NULLIF(melhor_horario,'') AS best_hour,
    NULLIF(iq_ciente_da_chaves_somente_na_vigencia,'') AS tenant_aware_of_entrance_only_in_entrance_date,
    NULLIF(iq_com_chave,'') AS tenant_with_key,
    TO_TIMESTAMP(NULLIF(ts_resposta_forms,''),'MM/dd/yyyy HH:mm:ss') AS ts_answer_form
FROM
    datalake_gsheets_raw.keys_logistic_onboarding_tenant