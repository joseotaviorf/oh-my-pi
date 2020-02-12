select 
  id,
  rev,
  revtype as rev_type,
  name,
  email,
  phone,
  user_id as id_user,
  user_id_mod as mod_id_user
from datalake_oscar_raw.referred_aud
