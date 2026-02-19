SELECT
    CAST(contrato AS BIGINT) AS id_contract,
    fraud_type,
    line,
    conclusion_status,
    source,
    to_timestamp(data_da_investigacao, 'dd/MM/yyyy') as dt_investigation
FROM
    datalake_gsheets_raw.fraud_contracts_for_rent