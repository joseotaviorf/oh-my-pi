WITH base_gsc AS (
  SELECT
    query as keyword,
    site_url,
    device,
    page,
    country,
    ctr,
    clicks,
    position,
    impressions,
    posimp,
    domain,
    struct AS structure,
    business_context,
    is_branded,
    dt_created,
    year,
    month,
    day
  FROM
    datalake_google_search_console_classified.seo_gsc_data
  WHERE
    DATE(dt_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
  keyword,
  -- Replaces the UDF SF_SET_ALPHANUMERIC_LOWER
  LOWER(
    REGEXP_REPLACE(
      TRANSLATE(
        keyword,
        'áàãâäéèêëíìîïóòõôöúùûüçñÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇÑ',
        'aaaaaeeeeiiiiooooouuuucnAAAAAEEEEIIIIOOOOOUUUUCN'
      ),
      '[^a-zA-Z0-9 ]',
      ''
    )
  ) AS keyword_clean,
  page,
  structure,
  business_context,
  site_url,
  device,
  domain,
  country,
  ctr,
  clicks,
  position,
  impressions,
  posimp,
  is_branded,
  dt_created,
  year,
  month,
  day
FROM
  base_gsc
GROUP BY ALL