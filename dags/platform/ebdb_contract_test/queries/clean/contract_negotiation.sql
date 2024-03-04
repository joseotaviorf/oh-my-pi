SELECT
       id,
       atualizadoEm AS ts_updated,
       criadoEm AS ts_created,
       durationUntil AS dt_duration_until,
       newValue AS new_value,
       status,
       type,
       contract_id AS id_contract,
       requestedBy_id AS id_requester,
       startsOn AS dt_started
FROM
       datalake_ebdb_test_raw.contractnegotiation
