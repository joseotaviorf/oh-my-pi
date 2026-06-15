SELECT
  id,
  image_inspection_id AS id_image_inspection,
  image_inspection_group_id AS id_image_inspection_group,
  lead_uuid AS uuid_lead,
  error AS error_message,
  created_at AS ts_created,
  image_attributes,
  urls,
  year,
  month,
  day
FROM
  datalake_kodak_raw.image_inspection_refine_history
