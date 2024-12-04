SELECT
    id,
    imovel_id AS id_house,
    leadConvertido_id AS id_converted_lead,
    vendedor_id AS id_sales_rep,
    REV AS rev,
    reVTYPE AS rev_type,
    status,
    tipo AS type,
    validado AS is_validated,
    status_MOD AS mod_status,
    validado_MOD AS mod_is_validated,
    dataConversao AS ts_conversion
FROM 
    datalake_ebdb_raw.ConversaoLead_aud