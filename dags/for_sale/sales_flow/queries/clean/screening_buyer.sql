SELECT
  id,
  screening_id AS id_screening,
  buyer_data_id AS id_buyer_data,
  status,
  proposal_validation_status,
  legal_pendency_note,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.screening_buyer
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}
    