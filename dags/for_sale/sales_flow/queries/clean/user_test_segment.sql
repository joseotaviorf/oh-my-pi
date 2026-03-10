SELECT
  id,
  person_uuid AS uuid_person,
  sales_flow_id AS id_sales_flow,
  test_segments,
  is_deleted,
  created_at AS ts_created,
  updated_at AS ts_updated,
  year,
  month,
  day
FROM
  datalake_sales_flow_raw.user_test_segment
