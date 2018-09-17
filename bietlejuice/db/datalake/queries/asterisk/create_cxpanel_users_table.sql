select
  cast(cxpanel_user_id as integer) as cxpanel_user_id,
  cast(user_id as integer) as user_id,
  display_name,
  peer,
  cast(add_extension as integer) as add_extension,
  cast("full" as integer) as "full",
  cast(add_user as integer) as add_user,
  hashed_password,
  initial_password,
  cast(auto_answer as integer) as auto_answer,
  cast(nullif(parent_user_id, '') as integer) as parent_user_id,
  cast(password_dirty as integer) as password_dirty
from datalake_raw.asterisk_cxpanel_users
;