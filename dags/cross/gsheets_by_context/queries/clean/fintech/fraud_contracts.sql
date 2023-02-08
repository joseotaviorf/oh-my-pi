SELECT 
    CAST(imovel AS BIGINT) AS id_house,
    CAST(contrato AS BIGINT) AS id_contract
FROM
    datalake_gsheets_raw.fraud_contracts