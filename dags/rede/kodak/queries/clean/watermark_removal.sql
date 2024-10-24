SELECT
  id,
  image_inspection_id AS id_image_inspection,
  provider,
  url,
  path,
  mask_active_pixels_ratio,
  noise_detected AS is_noise_detected,
  successful AS is_successful,
  chosen AS is_chosen,
  created_at AS ts_created,
  updated_at AS ts_updated
FROM
  datalake_kodak_raw.watermark_removal
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
