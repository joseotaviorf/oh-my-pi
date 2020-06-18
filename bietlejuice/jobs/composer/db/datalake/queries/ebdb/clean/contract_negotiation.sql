select
       id,
       atualizadoEm as ts_updated,
       criadoEm as ts_created,
       durationUntil as dt_duration_until,
       newValue as new_value,
       status,
       type,
       contract_id as id_contract,
       requestedBy_id as id_requester,
       startsOn as dt_started
from datalake_ebdb_raw.contractnegotiation
