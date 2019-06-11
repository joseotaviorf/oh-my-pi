select
  id,
  REV as rev,
  REVTYPE as rev_type,
  optedInAt as ts_opted_in,
  optedOutAt as ts_opted_out,
  specialConditionType as special_condition_type,
  imovel_id as id_house,
  expirationDate as ts_expired,
  specialConditionStatus as special_condition_status,
  specialConditionStatus_MOD+0 as special_condition_status_mod,
  optedInAt_MOD+0 as ts_opted_in_mod,
  optedOutAt_MOD+0 as ts_opted_out_mod,
  expirationDate_MOD+0 as ts_expired_mod,
  partner_id as id_partner,
  partner_MOD+0 as id_partner_mod
from SpecialCondition_AUD
;