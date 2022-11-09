select
  id,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  usuario_id as id_user,
  documentType as document_type,
  documentValue as document_value
from datalake_ebdb_raw.userdocument