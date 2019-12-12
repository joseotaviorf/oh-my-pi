SELECT
    id,
    dataCriacao AS ts_created,
    usuario_id AS id_user,
    vendedorResponsavel_id AS id_sales_responsible,
    corretorQueIndicou_id AS id_agent_referrer,
    afiliadoQueIndicou_id AS id_affiliate_referrer,
    salesforceContatoId AS id_contract_salesforce,
    tipoProprietario AS owner_type,
    atualizadoEm AS ts_updated,
    email,
    nome AS name,
    acceptWhatsApp AS has_accepted_whatsapp
FROM
    datalake_ebdb_raw.ProprietarioLead
