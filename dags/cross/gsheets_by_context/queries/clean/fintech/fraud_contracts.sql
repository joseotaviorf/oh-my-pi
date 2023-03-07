SELECT 
    CAST(imovel AS BIGINT) AS id_house,
    CAST(contrato AS BIGINT) AS id_contract,
    tipo_de_fraude AS fraud_type
FROM
    datalake_gsheets_raw.fraud_contracts