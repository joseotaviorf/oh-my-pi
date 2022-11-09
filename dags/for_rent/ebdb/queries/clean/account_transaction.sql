SELECT
    id AS id,
    dataCriacao AS ts_created,
    descricao AS description,
    tipo AS type,
    valor AS value,
    contaCorrente_id AS id_account,
    dataOperacao AS ts_transaction,
    imovel_id AS id_house,
    atualizadoEm AS ts_updated,
    despesa_id AS id_expense,
    paymentDate AS ts_payment,
    leadCampaign_id AS id_lead_campaign
FROM
    datalake_ebdb_raw.`OperacaoContaCorrente`