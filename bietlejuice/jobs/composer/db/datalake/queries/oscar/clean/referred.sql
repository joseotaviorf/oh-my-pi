select 
  id,
  created_at as ts_created,
  updated_at as ts_updated,
  name,
  email, 
  phone,
  user_id as id_user
from datalake_oscar_raw.referred
