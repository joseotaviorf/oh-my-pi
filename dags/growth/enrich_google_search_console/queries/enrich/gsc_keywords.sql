WITH base_gsc AS (
  SELECT
    dt_created,
    query AS keyword,
    page,
    google_property,
    branded,
    page_cluster,
    structure,
    page_path,
    state,
    city,
    location_level,
    search_region,
    poi_type,
    filter_count,
    filter_combination,
    position,
    CAST(impressions AS BIGINT) AS impressions,
    CAST(clicks AS BIGINT) AS clicks,
    ctr,
    posimp,
    site_url,
    device,
    domain,
    slug,
    subtitle_content,
    is_branded,
    year,
    month,
    day
  FROM
    datalake_google_search_console.seo_gsc_data
  WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  MAKE_DATE(YEAR(dt_created), MONTH(dt_created), 01) AS dt_created,
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
