SELECT
    NULLIF(codigo_imovel,'') AS id_house,
    NULLIF(ticket_id,'') AS id_ticket,
    NULLIF(type,'') AS agent_type,
    NULLIF(name,'') AS user_name,
    NULLIF(cpf,'') AS personal_document,
    NULLIF(email,'') AS user_email,
    NULLIF(telephone,'') AS user_telephone,
    NULLIF(pedido,'') AS first_request,
    NULLIF(pedido2,'') AS second_request,
    NULLIF(quantidade_de_chaves,'') AS number_of_keys,
    NULLIF(quantidade_de_kits,'') AS number_of_kits,
    NULLIF(endereco,'') AS house_address,
    NULLIF(numero,'') AS house_number,
    NULLIF(complemento,'') AS house_complement,
    NULLIF(bairro,'') AS house_neighborhood,
    NULLIF(cep,'') AS house_zipcode,
    NULLIF(cidade,'') AS house_city,
    NULLIF(estado,'') AS house_state,
    NULLIF(situacao_do_imovel,'') AS house_status,
    TO_TIMESTAMP(NULLIF(ts_criacao,''),'MM/dd/yyyy HH:mm:ss') AS ts_answer_form
FROM
    datalake_gsheets_raw.keys_logistic_pre_contract