WITH base_nps AS (
  SELECT
    ans.sk_nps_answer,
    disp.sk_user,
    ans.ts_answered,
    CAST(ts_answered AS DATE) AS data_resposta_nps,
    sent_date.date,
    DATEDIFF(TO_DATE(CAST(ts_answered AS DATE)), TO_DATE(sent_date.date)) AS days_to_answer,
    DATE_TRUNC('MONTH', CAST(ts_answered AS DATE)) AS month_year,
    pub.month,
    pub.year,
    disp.sk_contract,
    customer_type,
    metric_group AS campaign_nps,
    disp.score,
    score_category,
    categories.category,
    categories.theme,
    ans.comment,
    et.event_name
  FROM dw_customer_satisfaction.dim_nps_answer AS ans
  LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp
    ON ans.sk_nps_answer = disp.sk_nps_answer
  LEFT JOIN dw_public.dim_date AS sent_date
    ON sent_date.sk_date = disp.sk_sent_date
  INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS camp
    ON disp.sk_nps_campaign = camp.sk_nps_campaign
  INNER JOIN dw_public.dim_date AS pub
    ON disp.sk_answered_date = pub.sk_date
  LEFT JOIN dw_chattermill.fact_answer_category AS tags
    ON ans.sk_nps_answer = tags.sk_answer
  LEFT JOIN dw_chattermill.dim_answer_category AS categories
    ON tags.sk_category = categories.sk_category
  LEFT JOIN dw_rent.dim_contract AS c
    ON c.sk_contract = disp.sk_contract
  LEFT JOIN dw_rent.dim_rent_event_type AS et
    ON et.sk_event_type = disp.sk_last_rent_event_type
  WHERE
    disp.sk_nps_answer > 0
    AND camp.business_context = 'forRent'
    AND pub.year >= 2024
    AND camp.metric_group IN ('pplost', 'iqlostvisitas', 'iqlostpropostas', 'iqlost')
), listings AS (
  SELECT
    sk_owner,
    city_group
  FROM (
    SELECT
      sk_owner,
      city_group,
      ROW_NUMBER() OVER (PARTITION BY sk_owner ORDER BY sk_house_listing DESC) AS _w,
      sk_house_listing
    FROM dw_rent.fact_house_listings AS listings
    LEFT JOIN dw_public.dim_region AS dim
      ON listings.sk_region = dim.sk_region
  ) AS _t
  WHERE
    _w = 1
)
SELECT DISTINCT
  'Lost' AS nps_campanha,
  DATE_FORMAT(nps.data_resposta_nps, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  nps.sk_nps_answer AS feedback_id,
  nps.sk_user AS author_id,
  CONCAT(
    CAST(nps.sk_user AS STRING),
    '_',
    CASE WHEN nps.customer_type = 'IQ' THEN 'tenant' ELSE 'landlord' END
  ) AS account_id, /* nps.sk_contract, */
  CASE WHEN nps.customer_type = 'IQ' THEN 'tenant' ELSE 'landlord' END AS customer_type,
  nps.score AS rating,
  nps.score_category,
  list.city_group,
  CAST(CASE
    WHEN NULLIF(nps.comment, '') IS NULL
    THEN NULL
    WHEN nps.score BETWEEN 0 AND 6
    THEN CONCAT('Motivo da minha insatisfação: ', nps.comment)
    WHEN nps.score BETWEEN 7 AND 8
    THEN CONCAT('Motivo da minha nota: ', nps.comment)
    WHEN nps.score BETWEEN 9 AND 10
    THEN CONCAT('Motivo da minha satisfação: ', nps.comment)
    ELSE nps.comment
  END AS STRING) AS text,
  YEAR(TO_DATE(nps.data_resposta_nps)) AS year,
  MONTH(TO_DATE(nps.data_resposta_nps)) AS month,
  DAY(TO_DATE(nps.data_resposta_nps)) AS day,
  NOW() AS ts_load
FROM base_nps AS nps
LEFT JOIN listings AS list
  ON list.sk_owner = nps.sk_user
WHERE
  data_resposta_nps >= CAST('{load_start_date}' AS DATE)