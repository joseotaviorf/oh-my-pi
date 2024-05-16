SELECT
    id,
    contractId AS id_contract,
    requesterType AS requester_type,
    status,
    requestedStartDate AS dt_requested_started,
    previousStartDate AS dt_previous_started,
    criadoEm AS ts_created,
    atualizadoEm AS ts_updated
FROM
    datalake_ebdb_raw.contractStartDateRequest