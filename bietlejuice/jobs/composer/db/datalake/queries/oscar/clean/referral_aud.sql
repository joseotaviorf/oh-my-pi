select 
  id,
  rev,
  revtype as rev_type,
  house_summary_id as id_house_summary,
  referred_id as id_referred,
  referrer_id as id_referrer
from datalake_oscar_raw.referral_aud
