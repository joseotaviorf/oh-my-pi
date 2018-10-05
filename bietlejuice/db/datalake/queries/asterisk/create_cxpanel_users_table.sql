select
  cxpanel_user_id,
  user_id,
  display_name,
  peer,
  add_extension,
  "full",
  add_user,
  hashed_password,
  initial_password,
  auto_answer,
  nullif(parent_user_id, '') as parent_user_id,
  password_dirty
from datalake_raw.asterisk_cxpanel_users
;