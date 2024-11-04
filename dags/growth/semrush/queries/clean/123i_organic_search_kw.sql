SELECT
    CAST(_keyword AS STRING) AS keyword,
    CAST(_url AS STRING) AS url,
    CAST(_trends AS STRING) AS trends,
    CAST(_position AS INT) AS position,
    CAST(_previous__position AS INT) AS previous_position,
    CAST(_position__difference AS INT) AS position_difference,
    CAST(_intents AS STRING) AS keyword_intents,
    CAST(_position_type AS STRING) AS position_type,
    CAST(_s_e_r_p__features_by__position AS STRING) AS serp_features_by_position,
    CAST(_s_e_r_p__features_by__keyword AS STRING) AS serp_features_by_keyword,
    CAST(_search__volume AS INT) AS search_volume,
    CAST(_c_p_c AS DOUBLE) AS cpc,
    CAST(_traffic AS DOUBLE) AS traffic,
    CAST(_traffic_ AS DOUBLE) AS share_of_traffic,
    CAST(_traffic__cost_ AS DOUBLE) AS traffic_cost_percentage,
    CAST(_competition AS DOUBLE) AS competition,
    CAST(_number_of__results AS INT) AS number_of_results,
    CAST(_keyword__difficulty AS DOUBLE) AS keyword_difficulty,
    TO_DATE(date, 'yyyyMMdd') AS dt_report,
    TO_DATE(date, 'yyyyMMdd') AS dt_display,
    FROM_UNIXTIME(_timestamp, 'yyyy-MM-dd HH:mm:ss') AS ts_report,
    year AS year,
    month AS month,
    day AS day
FROM
    datalake_semrush_raw.searches
WHERE
    domain = '{domain}'
    AND year = {year}
    AND month = {month}