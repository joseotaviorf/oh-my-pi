SELECT
  id,
  screening_id AS id_screening,
  seller_data_id AS id_seller_data,
  status,
  proposal_validation_status,
  legal_pendency_note,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.screening_seller

