SELECT DISTINCT
  id_canvas AS sk_canvas,
  'affiliates' AS user_type,
  canvas_name,
  canvas_description,
  schedule_type,
  CAST(archived AS BOOLEAN) AS is_archived,
  CAST(draft AS BOOLEAN) AS is_draft,
  ts_first_entry,
  ts_last_entry,
  ts_created,
  ts_updated,
  NOW() AS ts_load
FROM
   datalake_braze_details_clean.canvas_details_indica_ai

UNION ALL

SELECT DISTINCT
  id_canvas AS sk_canvas,
  'owners' AS user_type,
  canvas_name,
  canvas_description,
  schedule_type,
  CAST(archived AS BOOLEAN) AS is_archived,
  CAST(draft AS BOOLEAN) AS is_draft,
  ts_first_entry,
  ts_last_entry,
  ts_created,
  ts_updated,
  NOW() AS ts_load
FROM
   datalake_braze_details_clean.canvas_details_owners
   
UNION ALL

SELECT DISTINCT
  id_canvas AS sk_canvas,
  'tenants' AS user_type,
  canvas_name,
  canvas_description,
  schedule_type,
  CAST(archived AS BOOLEAN) AS is_archived,
  CAST(draft AS BOOLEAN) AS is_draft,
  ts_first_entry,
  ts_last_entry,
  ts_created,
  ts_updated,
  NOW() AS ts_load
FROM
   datalake_braze_details_clean.canvas_details_tenants
