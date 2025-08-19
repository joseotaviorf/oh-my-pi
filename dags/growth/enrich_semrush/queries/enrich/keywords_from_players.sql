WITH players_data_from_semrush AS (
SELECT
    'quintoandar' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.quintoandar_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT DISTINCT -- There are duplicates in the source table
    'imovelweb' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.imovelweb_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT DISTINCT -- There are duplicates in the source table
    'zapimoveis' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.zapimoveis_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'vivareal' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.vivareal_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT DISTINCT -- There are duplicates in the source table
    'casamineira' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.casamineira_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'lopes' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.lopes_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'emcasa' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.emcasa_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT DISTINCT -- There are duplicates in the source table
    'chavesnamao' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.chavesnamao_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT DISTINCT -- There are duplicates in the source table
    'imoveisestadao' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.imoveisestadao_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'imoveismercadolivre' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.imoveismercadolivre_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'wimoveis' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.wimoveis_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    '123i' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.123i_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'trisul' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.trisul_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'ape11' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.ape11_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'arboimoveis' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.arboimoveis_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'imovelguide' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.imovelguide_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'direcional' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.direcional_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'auxiliadorapredial' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.auxiliadorapredial_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'secovi' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.secovi_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'loft' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.loft_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT DISTINCT -- There are duplicates in the source table
    'olximoveis' AS player,
    keyword,
    url,
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
    traffic_cost_percentage,
    competition,
    number_of_results,
    keyword_difficulty,
    dt_display,
    dt_report,
    ts_report,
    year,
    month,
    day
  FROM
    datalake_semrush_clean.olximoveis_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
)

SELECT
  player,
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

  url,
  REPLACE(REPLACE(trends, "["), "]") AS trends,
  position,
  previous_position,
  position_difference,

  -- Replaces the UDF FORMAT_KEYWORD_INTENT
  LOWER(
    ARRAY_JOIN(
      TRANSFORM(
        SPLIT(keyword_intents, ','),
        x -> CASE
          WHEN x = '0' THEN 'Commercial'
          WHEN x = '1' THEN 'Informational'
          WHEN x = '2' THEN 'Navigational'
          WHEN x = '3' THEN 'Transactional'
          ELSE x
        END
      ),
      ', '
    )
  ) AS keyword_intents,

  position_type,

  -- Replaces the UDF FORMAT_SERP_VALUES to the serp_features_by_position
  LOWER(
    ARRAY_JOIN(
      TRANSFORM(
        SPLIT(serp_features_by_position, ','),
        x -> CASE
          WHEN x = '0' THEN 'Instant answer'
          WHEN x = '1' THEN 'Knowledge panel'
          WHEN x = '2' THEN 'Carousel'
          WHEN x = '3' THEN 'Local pack'
          WHEN x = '4' THEN 'Top stories'
          WHEN x = '5' THEN 'Image pack'
          WHEN x = '6' THEN 'Site links'
          WHEN x = '7' THEN 'Reviews'
          WHEN x = '8' THEN 'Tweet'
          WHEN x = '9' THEN 'Video'
          WHEN x = '10' THEN 'Featured video'
          WHEN x = '11' THEN 'Featured Snippet'
          WHEN x = '13' THEN 'Image'
          WHEN x = '14' THEN 'AdWords top'
          WHEN x = '15' THEN 'AdWords bottom'
          WHEN x = '16' THEN 'Shopping ads'
          WHEN x = '17' THEN 'Hotels Pack'
          WHEN x = '18' THEN 'Jobs search'
          WHEN x = '19' THEN 'Featured images'
          WHEN x = '20' THEN 'Video Carousel'
          WHEN x = '21' THEN 'People also ask'
          WHEN x = '22' THEN 'FAQ'
          WHEN x = '23' THEN 'Flights'
          WHEN x = '24' THEN 'Find results on'
          WHEN x = '25' THEN 'Recipes'
          WHEN x = '27' THEN 'Twitter сarousel'
          WHEN x = '28' THEN 'Indented'
          WHEN x = '29' THEN 'News'
          WHEN x = '30' THEN 'Address Pack'
          WHEN x = '31' THEN 'Application'
          WHEN x = '32' THEN 'Events'
          WHEN x = '34' THEN 'Popular products'
          WHEN x = '35' THEN 'Related products'
          WHEN x = '36' THEN 'Related searches'
          WHEN x = '37' THEN 'See results about'
          WHEN x = '38' THEN 'Short videos'
          WHEN x = '39' THEN 'Web stories'
          WHEN x = '40' THEN 'Application list'
          WHEN x = '41' THEN 'Buying guide'
          WHEN x = '42' THEN 'Organic carousel'
          WHEN x = '43' THEN 'Things to know'
          WHEN x = '44' THEN 'Datasets'
          WHEN x = '45' THEN 'Discussions and forums'
          WHEN x = '46' THEN 'Explore brands'
          WHEN x = '47' THEN 'Questions and answers'
          WHEN x = '48' THEN 'Popular stores'
          WHEN x = '49' THEN 'Refine'
          WHEN x = '50' THEN 'People also search'
          WHEN x = '51' THEN 'Ads middle'
          WHEN x = '52' THEN 'AI overview'
          ELSE x
        END
      ),
      ', '
    )
  ) AS serp_features_by_position,

  -- Replaces the UDF FORMAT_SERP_VALUES to the serp_features_by_keyword
  LOWER(
    ARRAY_JOIN(
      TRANSFORM(
        SPLIT(serp_features_by_keyword, ','),
        x -> CASE
          WHEN x = '0' THEN 'Instant answer'
          WHEN x = '1' THEN 'Knowledge panel'
          WHEN x = '2' THEN 'Carousel'
          WHEN x = '3' THEN 'Local pack'
          WHEN x = '4' THEN 'Top stories'
          WHEN x = '5' THEN 'Image pack'
          WHEN x = '6' THEN 'Site links'
          WHEN x = '7' THEN 'Reviews'
          WHEN x = '8' THEN 'Tweet'
          WHEN x = '9' THEN 'Video'
          WHEN x = '10' THEN 'Featured video'
          WHEN x = '11' THEN 'Featured Snippet'
          WHEN x = '13' THEN 'Image'
          WHEN x = '14' THEN 'AdWords top'
          WHEN x = '15' THEN 'AdWords bottom'
          WHEN x = '16' THEN 'Shopping ads'
          WHEN x = '17' THEN 'Hotels Pack'
          WHEN x = '18' THEN 'Jobs search'
          WHEN x = '19' THEN 'Featured images'
          WHEN x = '20' THEN 'Video Carousel'
          WHEN x = '21' THEN 'People also ask'
          WHEN x = '22' THEN 'FAQ'
          WHEN x = '23' THEN 'Flights'
          WHEN x = '24' THEN 'Find results on'
          WHEN x = '25' THEN 'Recipes'
          WHEN x = '27' THEN 'Twitter сarousel'
          WHEN x = '28' THEN 'Indented'
          WHEN x = '29' THEN 'News'
          WHEN x = '30' THEN 'Address Pack'
          WHEN x = '31' THEN 'Application'
          WHEN x = '32' THEN 'Events'
          WHEN x = '34' THEN 'Popular products'
          WHEN x = '35' THEN 'Related products'
          WHEN x = '36' THEN 'Related searches'
          WHEN x = '37' THEN 'See results about'
          WHEN x = '38' THEN 'Short videos'
          WHEN x = '39' THEN 'Web stories'
          WHEN x = '40' THEN 'Application list'
          WHEN x = '41' THEN 'Buying guide'
          WHEN x = '42' THEN 'Organic carousel'
          WHEN x = '43' THEN 'Things to know'
          WHEN x = '44' THEN 'Datasets'
          WHEN x = '45' THEN 'Discussions and forums'
          WHEN x = '46' THEN 'Explore brands'
          WHEN x = '47' THEN 'Questions and answers'
          WHEN x = '48' THEN 'Popular stores'
          WHEN x = '49' THEN 'Refine'
          WHEN x = '50' THEN 'People also search'
          WHEN x = '51' THEN 'Ads middle'
          WHEN x = '52' THEN 'AI overview'
          ELSE x
        END
      ),
      ', '
    )
  ) AS serp_features_by_keyword,

  search_volume,
  cpc,
  traffic,
  share_of_traffic,
  traffic_cost_percentage,
  competition,
  number_of_results,
  keyword_difficulty,
  dt_display,
  dt_report,
  ts_report,
  year,
  month,
  day
FROM players_data_from_semrush
