SELECT
  id_house,
  is_listing_accurate,
  has_3p_access_control
FROM (
  SELECT
    id_house,
    is_listing_accurate,
    TRUE AS has_3p_access_control,
    ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY dt_change DESC) AS _w,
    dt_change
  FROM datalake_listing_accuracy_review.listing_accuracy_history
) AS _t
WHERE
  _w = 1