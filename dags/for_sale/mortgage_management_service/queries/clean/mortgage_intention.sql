SELECT
  id,
  mortgage_intention_uuid AS uuid_mortgage_intention,
  person_uuid AS uuid_person,
  source AS source_name,
  status AS status_name,
  mortgage_rules_country AS mortgage_rules_country_code,
  canceled_reason AS cancellation_reason,
  mortgage_term,
  expenses_amount,
  savings_amount,
  will_finance_expenses AS is_will_finance_expenses,
  will_use_savings AS is_will_use_savings,
  version,
  canceled_at AS ts_canceled,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_mortgage_management_service_raw.mortgage_intention
