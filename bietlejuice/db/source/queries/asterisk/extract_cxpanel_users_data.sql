select
  cxpanel_user_id,
  user_id,
  display_name,
  peer,
  add_extension,
  full,
  add_user,
  hashed_password,
  initial_password,
  auto_answer,
  parent_user_id,
  password_dirty
from asterisk.cxpanel_users
;