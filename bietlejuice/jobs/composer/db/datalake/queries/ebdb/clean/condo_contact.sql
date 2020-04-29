select
  id,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  nome as name,
  telefone as phone_number,
  tipo as type,
  condominio_id as id_condo
from datalake_ebdb_raw.contatocondominio