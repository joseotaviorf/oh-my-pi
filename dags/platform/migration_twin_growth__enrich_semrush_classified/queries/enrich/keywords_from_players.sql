WITH players_data_from_semrush AS (
SELECT
    'inmuebles24' AS player,
    'mex' AS country,
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
    datalake_semrush_classified_clean.inmuebles24_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'vivanuncios' AS player,
    'mex' AS country,
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
    datalake_semrush_classified_clean.vivanuncios_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'lamudi' AS player,
    'mex' AS country,
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
    datalake_semrush_classified_clean.lamudi_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'propiedades' AS player,
    'mex' AS country,
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
    datalake_semrush_classified_clean.propiedades_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'inmuebles' AS player,
    'mex' AS country,
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
    datalake_semrush_classified_clean.inmuebles_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'easyaviso' AS player,
    'mex' AS country,
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
    datalake_semrush_classified_clean.easyaviso_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'pincali' AS player,
    'mex' AS country,
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
    datalake_semrush_classified_clean.pincali_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'zonaprop' AS player,
    'arg' AS country,
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
    datalake_semrush_classified_clean.zonaprop_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'argenprop' AS player,
    'arg' AS country,
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
    datalake_semrush_classified_clean.argenprop_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'inmueblesmercadolibre' AS player,
    'arg' AS country,
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
    datalake_semrush_classified_clean.inmueblesmercadolibre_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'remax' AS player,
    'arg' AS country,
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
    datalake_semrush_classified_clean.remax_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'properati' AS player,
    'arg' AS country,
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
    datalake_semrush_classified_clean.properati_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'mudafy' AS player,
    'arg' AS country,
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
    datalake_semrush_classified_clean.mudafy_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'urbania' AS player,
    'per' AS country,
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
    datalake_semrush_classified_clean.urbania_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'adondevivir' AS player,
    'per' AS country,
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
    datalake_semrush_classified_clean.adondevivir_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'properatipe' AS player,
    'per' AS country,
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
    datalake_semrush_classified_clean.properatipe_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'infocasas' AS player,
    'per' AS country,
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
    datalake_semrush_classified_clean.infocasas_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'nexoinmobiliario' AS player,
    'per' AS country,
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
    datalake_semrush_classified_clean.nexoinmobiliario_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'plusvalia' AS player,
    'ecu' AS country,
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
    datalake_semrush_classified_clean.plusvalia_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'properatiec' AS player,
    'ecu' AS country,
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
    datalake_semrush_classified_clean.properatiec_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'icasas' AS player,
    'ecu' AS country,
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
    datalake_semrush_classified_clean.icasas_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'inmueblesmercadolibreec' AS player,
    'ecu' AS country,
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
    datalake_semrush_classified_clean.inmueblesmercadolibreec_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'compreoalquile' AS player,
    'pan' AS country,
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
    datalake_semrush_classified_clean.compreoalquile_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'encuentra24' AS player,
    'pan' AS country,
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
    datalake_semrush_classified_clean.encuentra24_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'panama_real_estate' AS player,
    'pan' AS country,
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
    datalake_semrush_classified_clean.panama_real_estate_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'inmopanama' AS player,
    'pan' AS country,
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
    datalake_semrush_classified_clean.inmopanama_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
UNION ALL
SELECT
    'panamaequity' AS player,
    'pan' AS country,
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
    datalake_semrush_classified_clean.panamaequity_organic_search_kw
  WHERE
    year = YEAR(DATE('{load_start_date}'))
    AND month = MONTH(DATE('{load_start_date}'))
)

SELECT
  pds.keyword,

  -- Replaces the UDF SF_SET_ALPHANUMERIC_LOWER
  LOWER(
    REGEXP_REPLACE(
      TRANSLATE(
        pds.keyword,
        'áàãâäéèêëíìîïóòõôöúùûüçÁÀÃÂÄÉÈÊËÍÌÎÏÓÒÕÔÖÚÙÛÜÇ',
        'aaaaaeeeeiiiiooooouuuucAAAAAEEEEIIIIOOOOOUUUUC'
      ),
      '[^a-zA-Z0-9 ]',
      ''
    )
  ) AS keyword_clean,

  pds.url,
  pds.player,
  pds.country,
  REPLACE(REPLACE(pds.trends, "["), "]") AS trends,
  pds.position,
  pds.previous_position,
  pds.position_difference,

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

  pds.position_type,

  -- Replaces the UDF FORMAT_SERP_VALUES to the serp_features_by_position
  LOWER(
    ARRAY_JOIN(
      TRANSFORM(
        SPLIT(pds.serp_features_by_position, ','),
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
        SPLIT(pds.serp_features_by_keyword, ','),
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

  pds.search_volume,
  pds.cpc,
  pds.traffic,
  pds.share_of_traffic,
  pds.traffic_cost_percentage,
  pds.competition,
  pds.number_of_results,
  pds.keyword_difficulty,
  pds.dt_display,
  pds.dt_report,
  pds.ts_report,
  pds.year,
  pds.month,
  pds.day
FROM players_data_from_semrush AS pds