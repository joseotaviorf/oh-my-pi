select
  id,
  agent,
  status,
  user_data,
  user_phone,
  source,
  source_env as source_environment,
  department,
  tags,
  context,
  created_by,
  last_message_at as ts_last_message,
  first_message_at as ts_first_message,
  created_at as ts_created,
  updated_at as ts_updated
from datalake_sauron_raw.session
