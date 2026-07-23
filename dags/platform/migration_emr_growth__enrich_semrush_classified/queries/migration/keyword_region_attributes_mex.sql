WITH cities AS (
  SELECT DISTINCT
    (
      city
    ),
    city_clean
  FROM datalake_gsheets_clean.mexico_regions
  WHERE
    NOT city IS NULL
), zones AS (
  SELECT DISTINCT
    (
      zone
    ),
    zone_clean
  FROM datalake_gsheets_clean.mexico_regions
  WHERE
    NOT zone IS NULL
), base_data AS (
  SELECT
    *
  FROM datalake_semrush_classified.keywords_from_players
  WHERE
    country = 'mex'
    AND year = YEAR(TO_DATE(CAST('{load_start_date}' AS DATE)))
    AND month = MONTH(TO_DATE(CAST('{load_start_date}' AS DATE)))
), general_state_level_enrichment AS (
  SELECT
    bd.*,
    CASE
      WHEN CONTAINS(keyword_clean, 'ciudad de mexico')
      THEN 'ciudad de mexico'
      WHEN keyword_clean RLIKE '.*(\\bcdmx\\b).*'
      THEN 'ciudad de mexico'
      ELSE NULL
    END AS match_state
  FROM base_data AS bd
), general_city_level_enrichment AS (
  SELECT
    match_city,
    *
  FROM (
    SELECT
      CASE
        WHEN keyword_clean RLIKE '.*(\\bgdl\\b).*'
        THEN COALESCE(c.city_clean, 'guadalajara')
        WHEN keyword_clean RLIKE '.*(\\bmty\\b).*'
        THEN COALESCE(c.city_clean, 'monterrey')
        WHEN keyword_clean RLIKE '.*(\\btj\\b).*'
        THEN COALESCE(c.city_clean, 'tijuana')
        WHEN keyword_clean RLIKE '.*(\\bqro\\b).*'
        THEN COALESCE(c.city_clean, 'queretaro')
        WHEN keyword_clean RLIKE '.*(\\bslp\\b).*'
        THEN COALESCE(c.city_clean, 'san luis potosi')
        WHEN keyword_clean RLIKE '.*(\\bgam\\b).*'
        THEN COALESCE(c.city_clean, 'gustavo a madero')
        WHEN CONTAINS(c.city_clean, 'casas')
        THEN NULL
        WHEN CONTAINS(c.city_clean, 'xico')
        THEN NULL
        WHEN CONTAINS(c.city_clean, ' ')
        THEN city_clean
        WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_clean))
        THEN city_clean
        ELSE COALESCE(c.city_clean, NULL)
      END AS match_city,
      gsle.*,
      ROW_NUMBER() OVER (PARTITION BY dt_report, keyword_clean, url ORDER BY LENGTH(
        CASE
          WHEN keyword_clean RLIKE '.*(\\bgdl\\b).*'
          THEN COALESCE(c.city_clean, 'guadalajara')
          WHEN keyword_clean RLIKE '.*(\\bmty\\b).*'
          THEN COALESCE(c.city_clean, 'monterrey')
          WHEN keyword_clean RLIKE '.*(\\btj\\b).*'
          THEN COALESCE(c.city_clean, 'tijuana')
          WHEN keyword_clean RLIKE '.*(\\bqro\\b).*'
          THEN COALESCE(c.city_clean, 'queretaro')
          WHEN keyword_clean RLIKE '.*(\\bslp\\b).*'
          THEN COALESCE(c.city_clean, 'san luis potosi')
          WHEN keyword_clean RLIKE '.*(\\bgam\\b).*'
          THEN COALESCE(c.city_clean, 'gustavo a madero')
          WHEN CONTAINS(c.city_clean, 'casas')
          THEN NULL
          WHEN CONTAINS(c.city_clean, 'xico')
          THEN NULL
          WHEN CONTAINS(c.city_clean, ' ')
          THEN city_clean
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_clean))
          THEN city_clean
          ELSE COALESCE(c.city_clean, NULL)
        END
      ) DESC, LOCATE(
        CASE
          WHEN keyword_clean RLIKE '.*(\\bgdl\\b).*'
          THEN COALESCE(c.city_clean, 'guadalajara')
          WHEN keyword_clean RLIKE '.*(\\bmty\\b).*'
          THEN COALESCE(c.city_clean, 'monterrey')
          WHEN keyword_clean RLIKE '.*(\\btj\\b).*'
          THEN COALESCE(c.city_clean, 'tijuana')
          WHEN keyword_clean RLIKE '.*(\\bqro\\b).*'
          THEN COALESCE(c.city_clean, 'queretaro')
          WHEN keyword_clean RLIKE '.*(\\bslp\\b).*'
          THEN COALESCE(c.city_clean, 'san luis potosi')
          WHEN keyword_clean RLIKE '.*(\\bgam\\b).*'
          THEN COALESCE(c.city_clean, 'gustavo a madero')
          WHEN CONTAINS(c.city_clean, 'casas')
          THEN NULL
          WHEN CONTAINS(c.city_clean, 'xico')
          THEN NULL
          WHEN CONTAINS(c.city_clean, ' ')
          THEN city_clean
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(c.city_clean))
          THEN city_clean
          ELSE COALESCE(c.city_clean, NULL)
        END,
        keyword_clean
      ) DESC) AS _w
    FROM general_state_level_enrichment AS gsle
    LEFT JOIN cities AS c
      ON LOCATE(LOWER(c.city_clean), LOWER(gsle.keyword_clean)) > 0
  ) AS _t
  WHERE
    _w = 1
), general_zone_level_enrichment AS (
  SELECT
    match_zone,
    *
  FROM (
    SELECT
      CASE
        WHEN CONTAINS(z.zone_clean, 'i')
        THEN ''
        WHEN CONTAINS(z.zone_clean, 'asa')
        THEN ''
        WHEN CONTAINS(z.zone_clean, 'mexico')
        THEN ''
        WHEN CONTAINS(z.zone_clean, 'de mexico')
        THEN ''
        WHEN CONTAINS(z.zone_clean, 'cu')
        THEN ''
        WHEN CONTAINS(z.zone_clean, 'raices')
        THEN ''
        WHEN CONTAINS(z.zone_clean, 'residencial')
        THEN ''
        WHEN CONTAINS(z.zone_clean, 'y')
        THEN ''
        WHEN CONTAINS(z.zone_clean, ' ')
        THEN zone_clean
        WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(z.zone_clean))
        THEN zone_clean
        ELSE COALESCE(z.zone_clean, '')
      END AS match_zone,
      gcle.*,
      ROW_NUMBER() OVER (PARTITION BY dt_report, keyword_clean, url ORDER BY LENGTH(
        CASE
          WHEN CONTAINS(z.zone_clean, 'i')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'asa')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'mexico')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'de mexico')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'cu')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'raices')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'residencial')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'y')
          THEN ''
          WHEN CONTAINS(z.zone_clean, ' ')
          THEN zone_clean
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(z.zone_clean))
          THEN zone_clean
          ELSE COALESCE(z.zone_clean, '')
        END
      ) DESC, LOCATE(
        CASE
          WHEN CONTAINS(z.zone_clean, 'i')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'asa')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'mexico')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'de mexico')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'cu')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'raices')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'residencial')
          THEN ''
          WHEN CONTAINS(z.zone_clean, 'y')
          THEN ''
          WHEN CONTAINS(z.zone_clean, ' ')
          THEN zone_clean
          WHEN ARRAY_CONTAINS(SPLIT(keyword_clean, ' '), LOWER(z.zone_clean))
          THEN zone_clean
          ELSE COALESCE(z.zone_clean, '')
        END,
        keyword_clean
      ) DESC) AS _w
    FROM general_city_level_enrichment AS gcle
    LEFT JOIN zones AS z
      ON LOCATE(LOWER(z.zone_clean), LOWER(gcle.keyword_clean)) > 0
  ) AS _t
  WHERE
    _w = 1
)
SELECT
  keyword,
  keyword_clean,
  url,
  COALESCE(match_city, match_state, '') AS match_city,
  match_zone,
  player,
  trends,
  position,
  previous_position,
  position_difference,
  keyword_intents,
  position_type,
  serp_features_by_position,
  serp_features_by_keyword,
  search_volume,
  cpc,
  traffic,
  share_of_traffic,
  competition,
  number_of_results,
  keyword_difficulty,
  CASE WHEN COALESCE(match_city, match_state, '') <> '' THEN 1 ELSE 0 END AS has_mention_to_city,
  CASE WHEN match_zone <> '' THEN 1 ELSE 0 END AS has_mention_to_zone,
  dt_display,
  dt_report,
  ts_report,
  year,
  month,
  day
FROM general_zone_level_enrichment