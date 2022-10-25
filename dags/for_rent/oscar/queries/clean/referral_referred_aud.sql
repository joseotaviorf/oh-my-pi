select 
  referral_id as id_referral,
  referred_id as id_referred,
  rev,
  revtype as rev_type,
  contract_signed_at as ts_contract_signed,
  contract_signed_at_mod as mod_ts_contract_signed,
  rent_value as rent,
  rent_value_mod as mod_rent
from datalake_oscar_raw.referral_referred_aud
