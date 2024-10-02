select
  id,
  entrance_id as id_entrance,
  comment,
  submitted as is_submitted,
  visittype as visit_type,
  criadoem as ts_created,
  atualizadoem as ts_updated
from datalake_ebdb_test_raw.FollowUpDetails
