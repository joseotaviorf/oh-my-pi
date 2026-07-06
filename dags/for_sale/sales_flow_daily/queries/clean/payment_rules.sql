SELECT
  -- ids
  id,
  -- non-ids
  payment_id AS id_payment,
  -- non metrics
  cash_first_installment_day_count_type,
  cash_second_installment_condition,
  cash_second_installment_day_count_type,
  cash_value_payment_extension_markdown,
  entry_amount_first_installment_day_count_type,
  entry_amount_second_installment_condition,
  entry_amount_second_installment_day_count_type,
  entry_amount_payment_extension_markdown,
  entry_amount_payment_extension_day_count_type,
  down_payment_day_count_type,
  cash_value_payment_extension_day_count_type,
  -- metrics
  down_payment_term,
  cash_first_installment_value,
  cash_first_installment_term,
  cash_second_installment_value,
  cash_second_installment_term,
  cash_value_payment_extension_term,
  entry_amount_first_installment_value,
  entry_amount_first_installment_term,
  entry_amount_second_installment_value,
  entry_amount_second_installment_term,
  entry_amount_payment_extension_term,
  -- bool
  has_down_payment_extension,
  has_cash_value_installment,
  has_cash_value_payment_extension,
  has_entry_amount_installment,
  has_entry_amount_payment_extension,
  -- dates
  -- timestamps
  created_at AS ts_created,
  updated_at AS ts_updated,
  -- partitioning
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.payment_rules