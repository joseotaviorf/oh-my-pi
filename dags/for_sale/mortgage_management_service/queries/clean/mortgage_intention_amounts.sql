SELECT
  id,
  mortgage_intention_id AS id_mortgage_intention,
  source AS source_name,
  currency AS currency_code,
  event_source_id AS event_source_reference_id,
  financed_amount,
  down_payment,
  property_value,
  version,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_intention_amounts
