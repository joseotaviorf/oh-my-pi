SELECT
  GET_JSON_OBJECT(ids, '$.id_recset_fix') AS id_recset_fix,
  CAST(GET_JSON_OBJECT(ids, '$.id_house') AS INT) AS id_house,
  GET_JSON_OBJECT(dimensions, '$.business_context') AS business_context,
  GET_JSON_OBJECT(dimensions, '$.city') AS house_city,
  GET_JSON_OBJECT(dimensions, '$.platform') AS platform,
  GET_JSON_OBJECT(dimensions, '$.country') AS country,
  GET_JSON_OBJECT(dimensions, '$.position') AS listing_position_in_recset,
  GET_JSON_OBJECT(dimensions, '$.showcase') AS showcase,
  GET_JSON_OBJECT(dimensions, '$.origin') AS origin,
  GET_JSON_OBJECT(dimensions, '$.listing_age') AS listing_age,
  CASE WHEN GET_JSON_OBJECT(metrics, '$.click') = '1' THEN TRUE ELSE FALSE END AS listing_clicked,
  ts_event AS ts_recommendation_event,
  year,
  month,
  day
FROM datalake_search.recs_impressions_processed
WHERE MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_7}) AND DATE('{end_date}')