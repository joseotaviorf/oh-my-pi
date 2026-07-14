SELECT
  id,
  trigger_id AS uuid_trigger_id,
  user_id AS id_user,
  phone_number,
  chatbot,
  intent,
  trigger_event,
  outcome,
  created_at AS ts_created
FROM
  datalake_house_listing_search_raw.concierge_trigger
