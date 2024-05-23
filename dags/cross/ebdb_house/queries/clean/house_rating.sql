select
  id,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  complementaryInfo as complementary_info,
  rating
from datalake_ebdb_raw.houserating