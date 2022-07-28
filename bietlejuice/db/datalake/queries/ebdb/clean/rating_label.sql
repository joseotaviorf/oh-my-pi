select
  id,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  description,
  label,
  ratingReference as rating_reference,
  ratingTarget as rating_target,
  requireComplementaryInfo as has_complementary_info_requirement,
  active as is_active,
  order
from datalake_ebdb_raw.ratinglabel