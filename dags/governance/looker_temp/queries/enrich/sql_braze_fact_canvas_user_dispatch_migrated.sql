SELECT
  f.*,
  d.canvas_name,
  d.variant_name,
  d.canvas_description,
  d.schedule_type,
  d.is_archived,
  d.is_draft,
  d.ts_first_entry,
  d.ts_last_entry,
  d.ts_created,
  d.ts_updated,
  ROW_NUMBER() OVER (PARTITION BY f.sk_user_dispatch, f.sk_canvas ORDER BY f.ts_load DESC) AS row_number
FROM dw_braze.fact_canvas_user_dispatch AS f
LEFT JOIN dw_braze.dim_canvas AS d
  ON f.sk_variant_canvas = d.sk_variant_canvas