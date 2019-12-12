SELECT
    id,
    dataConversao AS ts_conversion,
    imovel_id AS id_house,
    leadConvertido_id AS id_converted_lead,
    vendedor_id AS id_sales_rep,
    gerenteContas_id AS id_account_manager,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    validado AS is_validated,
    status,
    tipo AS type
FROM datalake_ebdb_raw.ConversaoLead
