SELECT
    id,
    validationId AS id_validation,
    validationStatus AS validation_status,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.`bankaccountvalidation`
