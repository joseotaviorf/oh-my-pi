WITH base_gsc AS (
  SELECT
    sgd.dt_created,
    sgd.query AS keyword,
    sgd.page,
    sgd.google_property,
    sgd.branded,
    sgd.page_cluster,
    sgd.structure,
    sgd.page_structure,
    sgd.page_path,
    sgd.state,
    sgd.city,
    sgd.location_level,
    sgd.search_region,
    sgd.poi_type,
    sgd.filter_count,
    sgd.filter_combination,
    sgd.position,
    CAST(sgd.impressions AS BIGINT) AS impressions,
    CAST(sgd.clicks AS BIGINT) AS clicks,
    sgd.ctr,
    sgd.posimp,
    sgd.site_url,
    sgd.device,
    sgd.domain,
    sgd.slug,
    sgd.subtitle_content,
    sgd.is_branded,
    CASE WHEN sg.keyword IS NOT NULL
      THEN TRUE
      ELSE FALSE
    END AS is_goldenset,
    sgd.year,
    sgd.month,
    sgd.day
  FROM
    datalake_google_search_console.seo_gsc_data AS sgd
  LEFT JOIN
    datalake_gsheets_clean.seo_goldenset AS sg
      ON sgd.query = sg.keyword 
        AND sgd.dt_created BETWEEN sg.dt_effective_start AND COALESCE(sg.dt_effective_end, CURRENT_DATE())
  WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  dt_created,
  keyword,

  -- Replaces the UDF SF_SET_ALPHANUMERIC_LOWER
  LOWER(
    REGEXP_REPLACE(
      TRANSLATE(
        keyword,
        'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ',
        'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'
      ),
      '[^a-zA-Z0-9 ]',
      ''
    )
  ) AS keyword_clean,

  page,
  google_property,
  branded,
  page_cluster,
  structure,
  page_structure,
  page_path,
  state,
  city,
  location_level,
  search_region,
  poi_type,
  filter_count,
  filter_combination,
  site_url,
  device,
  domain,
  slug,
  subtitle_content,
  is_branded,
  is_goldenset,
  ctr,
  clicks,
  position,
  impressions,
  posimp,
  year,
  month,
  day
FROM
  base_gsc
