select
    id
    ,inicioContrato as ts_contract_started
    ,tipoContrato as contract_type
    ,ativo as is_active
    ,atualizadoEm as ts_updated
    ,criadoEm as ts_created
    ,preferenciaPagamento as payment_preference
from
    datalake_ebdb_raw.dadosfotografo -- TODO [ODS] Rename this table from photographer to PhotographerData on clean
