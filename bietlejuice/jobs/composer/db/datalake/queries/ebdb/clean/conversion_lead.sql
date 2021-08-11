SELECT
    id,
    imovel_id AS id_house,
    leadConvertido_id AS id_converted_lead,
    vendedor_id AS id_sales_rep,
    gerenteContas_id AS id_account_manager,
    validado AS is_validated,
    status,
    tipo AS type,
    dataConversao AS ts_conversion,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM datalake_ebdb_raw.ConversaoLead
