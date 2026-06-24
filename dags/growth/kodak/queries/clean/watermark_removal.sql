WITH ranked AS (
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
    failure_reason,
    created_at AS ts_created,
    updated_at AS ts_updated,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY updated_at DESC) AS rn
  FROM
    datalake_kodak_raw.watermark_removal
)
SELECT
  id,
  id_image_inspection,
  provider,
  url,
  path,
  mask_active_pixels_ratio,
  is_noise_detected,
  is_successful,
  is_chosen,
  failure_reason,
  ts_created,
  ts_updated,
  op_cdc,
  ts_cdc_transaction,
  ts_database_transaction
FROM
  ranked
WHERE
  rn = 1
