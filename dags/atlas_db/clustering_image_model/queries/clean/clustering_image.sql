SELECT
  condo AS id_condo,
  sourcenameid_anchor AS id_sourcename_anchor,
  sourcenameid_pair AS id_sourcename_pair,
  unit_anchor,
  unit_pair,
  building_anchor,
  building_pair,
  photos_anchor,
  photos_pair,
  similarity,
  ypred,
  check_metadata,
  ypred_using_metadata,
  db_to_filter,
  model_metadata,
  dt_model,
  year,
  month,
  day
FROM
  datalake_clustering_image_model_raw.clustering_image
WHERE
  MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
  ROW_NUMBER() OVER (
    PARTITION BY id_sourcename_anchor, id_sourcename_pair
    ORDER BY dt_model DESC
  ) = 1
