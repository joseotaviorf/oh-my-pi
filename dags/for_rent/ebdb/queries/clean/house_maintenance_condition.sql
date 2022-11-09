select
  id,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  maintenanceCondition as maintenance_condition,
  houseId as id_house
from datalake_ebdb_raw.housemaintenancecondition