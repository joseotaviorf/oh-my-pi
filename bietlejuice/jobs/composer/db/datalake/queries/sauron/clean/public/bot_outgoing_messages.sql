select
  id,
  session_id as id_session,
  message_id as id_message,
  message_payload,
  bot_response,
  user_phone,
  year_month,
  created_at as ts_created,
  updated_at as ts_updated
from datalake_sauron_raw.botoutgoingmessages