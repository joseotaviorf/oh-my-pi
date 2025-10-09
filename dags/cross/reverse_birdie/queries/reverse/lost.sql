WITH base_nps as (
  SELECT 
    ans.sk_nps_answer, 
    disp.sk_user, 
    ans.ts_answered, 
    date(ts_answered) as data_resposta_nps, 
    sent_date.date, 
    date_diff(
      DAY, 
      sent_date.date, 
      date(ts_answered)
    ) as days_to_answer, 
    date_trunc(
      'month', 
      date(ts_answered)
    ) as month_year, 
    pub.month, 
    pub.year, 
    disp.sk_contract, 
    customer_type, 
    metric_group as campaign_nps, 
    disp.score, 
    score_category, 
    categories.category, 
    categories.theme, 
    ans.comment, 
    et.event_name 
  FROM dw_customer_satisfaction.dim_nps_answer AS ans 
  LEFT JOIN dw_customer_satisfaction.fact_nps_dispatches AS disp 
    ON ans.sk_nps_answer = disp.sk_nps_answer 
  LEFT JOIN dw_public.dim_date as sent_date 
    on sent_date.sk_date = disp.sk_sent_date 
  INNER JOIN dw_customer_satisfaction.dim_nps_campaign AS camp 
    ON disp.sk_nps_campaign = camp.sk_nps_campaign 
  INNER JOIN dw_public.dim_date AS pub 
    ON disp.sk_answered_date = pub.sk_date 
  LEFT JOIN dw_chattermill.fact_answer_category tags 
    ON ans.sk_nps_answer = tags.sk_answer 
  LEFT JOIN dw_chattermill.dim_answer_category categories 
    ON tags.sk_category = categories.sk_category 
  LEFT JOIN dw_rent.dim_contract c 
    ON c.sk_contract = disp.sk_contract 
  LEFT JOIN dw_rent.dim_rent_event_type et 
    ON et.sk_event_type = disp.sk_last_rent_event_type 
  WHERE 
    disp.sk_nps_answer > 0 
    and camp.business_context = 'forRent' 
    and pub.year >= 2024 
    and camp.metric_group in (
      'pplost',
      'iqlostvisitas',
      'iqlostpropostas', 
      'iqlost'
    )
),
listings as (
SELECT
  sk_owner,
  city_group 
FROM dw_rent.fact_house_listings AS listings
LEFT JOIN dw_public.dim_region AS dim 
  ON listings.sk_region = dim.sk_region
QUALIFY
   ROW_NUMBER() OVER (PARTITION BY sk_owner ORDER BY sk_house_listing DESC) = 1
)
SELECT 
  distinct
  'Lost'  as nps_campanha, 
  date_format(nps.data_resposta_nps, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  nps.sk_nps_answer as feedback_id, 
  nps.sk_user as author_id, 
 -- nps.sk_contract,
  CONCAT(CAST(nps.sk_user AS STRING), '_', CASE WHEN nps.customer_type = 'IQ' THEN 'tenant' ELSE 'landlord' END) AS account_id,
  case when nps.customer_type = 'IQ' then 'tenant' else 'landlord' end as customer_type,
  nps.score as rating, 
  nps.score_category,
  list.city_group,
 CAST(
    case 
      when NULLIF(nps.comment, '') is null then null
      when nps.score between 0 and 6 then CONCAT('Motivo da minha insatisfação: ', nps.comment)
      when nps.score between 7 and 8 then CONCAT('Motivo da minha nota: ', nps.comment)
      when nps.score between 9 and 10 then CONCAT('Motivo da minha satisfação: ', nps.comment)
      else nps.comment
    end 
  AS VARCHAR(1000000)) AS text,
  year(nps.data_resposta_nps) AS year,
  month(nps.data_resposta_nps) AS month,
  day(nps.data_resposta_nps) AS day,
  NOW() AS ts_load
FROM base_nps as nps
LEFT JOIN listings AS list 
  on list.sk_owner = nps.sk_user
WHERE 
  data_resposta_nps >= DATE('{load_start_date}')