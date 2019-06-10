select
  id,
  atualizadoEm as ts_updated,
  criadoEm as ts_created,
  optedInAt as ts_opted_id,
  optedOutAt as ts_opted_out,
  imovel_id as id_house,
  specialConditionType as special_condition_type,
  expirationDate as ts_expired,
  specialConditionStatus as special_condition_status,
  partner_id as id_partner
from SpecialCondition
;