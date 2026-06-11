WITH clicked_properties as (
  SELECT
    id_user,
    ts_event,
    get_json_object(event_properties, '$.business_context') as business_context,
    get_json_object(event_properties, '$.house_id') as house_id,
    get_json_object(event_properties, '$.recset_id') as recommendation_id,
    CAST(REGEXP_REPLACE(get_json_object(event_properties, '$.recitem_rank'), '[^0-9]', '') AS INT) as rank
  FROM datalake_amplitude_clean.170698_listing_page_viewed_events
  WHERE
    get_json_object(event_properties, '$.recset_showcase') = 'CONCIERGE_WHATSAPP'
    and make_date(year, month, day) < '{load_start_date}'
    and make_date(year, month, day) >= DATE_SUB('{load_start_date}', 4)

),

base as (
  SELECT
    ruuc.ts_created,
    ruuc.id_user,
    ruuc.id_recommendation,
    ruc.id_listing,
    ruc.displayed_order+1 as rank,
    CASE WHEN cp.house_id is not null THEN 1 ELSE 0 END as clicked
  FROM datalake_house_listing_search_clean.recommendation_user_use_case ruuc
  LEFT JOIN datalake_house_listing_search_clean.recommendation_use_case ruc
    on ruuc.id=ruc.id_user_use_case
    and CAST(ruc.ts_created AS DATE) = DATE_SUB('{load_start_date}', 4)
  LEFT JOIN clicked_properties cp
    on cp.house_id = ruc.id_listing
    and cp.recommendation_id=ruuc.id_recommendation
    -- and cp.id_user=ruuc.id_user -- we should not join by user because sometimes the user id is not present on the LPV
                                   -- after coming from a Concierge rec
  WHERE
    ruuc.id_recommendation is not null
    AND ruc.id_listing is not null
    AND ruuc.use_case in ('FEED_CONCIERGE', 'FEED_MULTI_ORIGIN_PERSONALIZED_TRANSACTIONAL', 'FEED_MULTI_ORIGIN_PERSONALIZED_CLASSIFIED', 'FEED_MULTI_ORIGIN_SIMILAR_TRANSACTIONAL', 'FEED_MULTI_ORIGIN_SIMILAR_CLASSIFIED')
    AND upper(COALESCE(ruuc.origin, 'JULIA')) = upper('JULIA')
    AND CAST(ruuc.ts_created AS DATE) = DATE_SUB('{load_start_date}', 4)
  GROUP by all -- this is needed because we sometimes have duplicates on our tracking and not having this was leading to
               -- having an ndcg and recall bigger than 1
),

metrics AS (
  SELECT
    ts_created,
    id_user,
    id_recommendation,
    SUM(CASE WHEN rank <= 3 AND clicked = 1 THEN 1 ELSE 0 END) AS hits_at_3,
    COUNT(DISTINCT CASE WHEN clicked = 1 THEN id_listing END) AS total_clicks,
    SUM(CASE WHEN rank <= 3 THEN clicked / LOG2(rank + 1) ELSE 0 END) AS dcg_at_3
  FROM base
  GROUP BY
    id_user,
    id_recommendation,
    ts_created
),

ideal_dcg AS (
  SELECT
    ts_created,
    id_user,
    id_recommendation,
    SUM(1 / LOG2(pos + 1)) as idcg_at_3

  FROM (
    SELECT
      ts_created,
      id_user,
      id_recommendation,
      ROW_NUMBER() OVER (PARTITION BY id_user, id_recommendation ORDER BY clicked DESC) as pos
    FROM base
    WHERE clicked = 1
  ) sub
  WHERE pos <= 3
  GROUP BY
    ts_created,
    id_user,
    id_recommendation
)

SELECT
  m.ts_created,
  m.id_user,
  m.id_recommendation,
  CASE WHEN m.total_clicks > 0 THEN m.hits_at_3 / m.total_clicks ELSE 0 END AS recall_at_3,
  CASE WHEN i.idcg_at_3 > 0 THEN m.dcg_at_3 / i.idcg_at_3 ELSE 0 END AS ndcg_at_3,
  year(m.ts_created) AS year,
  month(m.ts_created) AS month,
  day(m.ts_created) AS day
FROM metrics m
LEFT JOIN ideal_dcg i
  ON m.ts_created = i.ts_created
  AND m.id_user = i.id_user
  AND m.id_recommendation = i.id_recommendation

