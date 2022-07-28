select 
  referral_id as id_referral,
  referred_id as id_referred,
  contract_signed_at as ts_contract_signed,
  rent_value as rent,
  status
from datalake_oscar_raw.referral_referred