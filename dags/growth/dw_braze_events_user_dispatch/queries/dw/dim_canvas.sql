WITH
exploded_indica_ai_variants AS (
SELECT 
    id_canvas,
    canvas_name,
    canvas_description,
    schedule_type,
    archived,
    draft,
    ts_first_entry,
    ts_last_entry,
    ts_created,
    ts_updated,
    EXPLODE(variants) AS variant
FROM
    datalake_braze_details_clean.canvas_details_indica_ai
),

exploded_owners_variants AS (
SELECT 
    id_canvas,
    canvas_name,
    canvas_description,
    schedule_type,
    archived,
    draft,
    ts_first_entry,
    ts_last_entry,
    ts_created,
    ts_updated,
    EXPLODE(variants) AS variant
FROM
    datalake_braze_details_clean.canvas_details_owners
),

exploded_tenants_variants AS (
SELECT 
    id_canvas,
    canvas_name,
    canvas_description,
    schedule_type,
    archived,
    draft,
    ts_first_entry,
    ts_last_entry,
    ts_created,
    ts_updated,
    EXPLODE(variants) AS variant
FROM
    datalake_braze_details_clean.canvas_details_tenants
)

SELECT DISTINCT
  variant.id AS sk_variant_canvas, 
  id_canvas AS sk_canvas,
  'affiliates' AS user_type,
  canvas_name,
  variant.name AS variant_name, 
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
  exploded_indica_ai_variants
  
UNION ALL

SELECT DISTINCT
  variant.id AS sk_variant_canvas, 
  id_canvas AS sk_canvas,
  'owners' AS user_type,
  canvas_name,
  variant.name AS variant_name, 
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
  exploded_owners_variants
  
UNION ALL

SELECT DISTINCT
  variant.id AS sk_variant_canvas, 
  id_canvas AS sk_canvas,
  'tenants' AS user_type,
  canvas_name,
  variant.name AS variant_name, 
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
  exploded_tenants_variants
