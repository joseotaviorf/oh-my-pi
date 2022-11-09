select
    id,
    tipoContrato as contract_type,
    preferenciaPagamento as payment_preference,
    ativo as is_active,
    inicioContrato as ts_contract_started,
    criadoEm as ts_created,
    atualizadoEm as ts_updated
from datalake_ebdb_raw.dadosfotografo
