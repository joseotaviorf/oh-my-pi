SELECT
    id_entity,
    manual_eval,
    requester,
    aproved_by,
    justification,
    to_timestamp(ts_ingested) as ts_ingested
FROM
    datalake_gsheets_raw.anonymization_manual_validation
