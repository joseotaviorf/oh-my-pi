-- IN THIS TABLE WE HAVE VERSIONS 050 AND 030 FOR BOTH ITAÚ AND BRADESCO
SELECT
    id_bank,
    id_service_batch,
    record_type,
    CAST(SUBSTRING(metadata, 10, 6) AS INTEGER) AS file_batch_amount,
    CAST(SUBSTRING(metadata, 16, 6) AS INTEGER) AS file_registers_amount,
    CAST(SUBSTRING(metadata, 22, 6) AS INTEGER) AS file_accounts_amount,
    year,
    month,
    day
FROM
    datalake_nexxera_raw.financial_extracts
WHERE
    id_bank IN (341, 237)
    AND id_service_batch = '9999'
    AND record_type = 9
    AND CONCAT(year,month,day) <> 20181120 -- on this date we have the layouts 081 and 080, these versions need a different structure of fields
