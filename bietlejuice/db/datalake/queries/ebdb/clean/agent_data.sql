select
    id,
    ativo as is_active,
    coordinateId as id_coordinate,
    salesForceId as id_salesforce,
    perfil as profile,
    cidade_id as id_city,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    numeroCRECI as creci_number,
    edicaoAgendaBloqueada as blocked_schedule_edition,
    workContract_id as id_work_contract,
    preferredRegion_id as id_preferred_region
from
    datalake_ebdb_raw.dadosagente