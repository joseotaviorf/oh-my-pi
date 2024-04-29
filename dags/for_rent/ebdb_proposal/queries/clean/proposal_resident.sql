select
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    cpf,
    dataNascimento as dt_birth,
    email,
    nome as name,
    rg,
    telefone as phone_number,
    proposta_id as id_proposal
from
    datalake_ebdb_raw.propostamorador