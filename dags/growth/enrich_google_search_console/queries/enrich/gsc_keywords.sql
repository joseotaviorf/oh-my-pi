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
    impressions,
    clicks,
    ctr,
    site_url,
    posimp,
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
  year,
  month,
  day,
  SUM(posimp) / SUM(impressions) AS position,
  SUM(impressions) AS impressions,
  SUM(clicks) AS clicks,
  SUM(clicks) / SUM(impressions) AS ctr,
  SUM(posimp) AS posimp
FROM
  base_gsc
GROUP BY ALL
