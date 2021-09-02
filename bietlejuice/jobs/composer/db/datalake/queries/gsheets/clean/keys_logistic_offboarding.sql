SELECT
    NULLIF(codigo_contrato, '') AS id_contract,
    NULLIF(cod_imovel, '') AS id_house,
    NULLIF(nome_pp, '') AS owner_name,
    NULLIF(telefone_cadastro_pp , '') AS owner_phone,
    NULLIF(melhor_horario, '') AS best_hour,
    NULLIF(endereco, '') AS house_address,
    NULLIF(numero, '') AS house_number,
    NULLIF(complemento, '') AS house_complement,
    NULLIF(cep, '') AS house_zipcode,
    NULLIF(bairro, '') AS house_neighborhood,
    NULLIF(cidade, '') AS house_city,
    TO_TIMESTAMP(NULLIF(ts_resposta_forms,''),'MM/dd/yyyy HH:mm:ss') AS ts_answer_form
FROM
    datalake_gsheets_raw.keys_logistic_offboarding