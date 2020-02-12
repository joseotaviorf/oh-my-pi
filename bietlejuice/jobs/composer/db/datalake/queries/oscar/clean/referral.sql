select 
  id,
  created_at as ts_created,
  updated_at as ts_updated,
  house_summary_id as id_house_summary,
  referrer_id as id_referrer
from datalake_oscar_raw.referral
