SELECT
    NULLIF(codigo_jitex,'') AS id_jitex,
    NULLIF(email_ticket,'') AS email_or_ticket,
    NULLIF(canal_solicitante,'') AS requesting_channel,
    INT(NULLIF(quantidade_solicitada,'')) AS requested_quantity,
    NULLIF(tipo_de_contato,'') AS type_of_contact,
    NULLIF(nome,'') AS name,
    BIGINT(NULLIF(telefone,'')) AS phone,
    NULLIF(endereco,'') AS house_address,
    NULLIF(bairro,'') AS house_neighborhood,
    NULLIF(cep,'') AS house_zipcode,
    NULLIF(uf,'') AS house_state,
    NULLIF(cidade,'') AS house_city,
    NULLIF(complemento,'') AS house_complement,
    NULLIF(status_tratativa,'') AS status_deal,
    NULLIF(motivo_status,'') AS status_reason,
    NULLIF(obs_movimentacao_chaves,'') AS keys_logistic_comments,
    NULLIF(canal,'') AS channel,
    TO_TIMESTAMP(NULLIF(data_solicitacao,''),'dd/MM/yyyy HH:mm:ss') AS ts_request,
    TO_DATE(NULLIF(data_ultima_tratativa,''),'dd/MM/yyyy') AS dt_last_deal,
    TO_DATE(NULLIF(data_transporte,''),'dd/MM/yyyy') AS dt_transport
FROM
    datalake_gsheets_raw.keys_logistic_funil
