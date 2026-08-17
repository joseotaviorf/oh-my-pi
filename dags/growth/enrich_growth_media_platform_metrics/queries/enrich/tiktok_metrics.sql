SELECT
  -- Dimensions
  id_advertiser AS id_account,
  id_campaign,
  id_adgroup AS id_adset,
  id_ad AS id_ad,
  CASE 
      WHEN id_advertiser = 6959164232126480386 THEN 'Demand'
      WHEN id_advertiser = 7565961310706794513 THEN 'Supply'
    ELSE CAST(NULL AS STRING)
  END AS account_name,
  'tiktok' AS origin,
  'tiktok_campaigns' AS report_type,
  campaign_name AS utm_campaign,
  adgroup_name AS utm_term,
  ad_name AS utm_content,
  -- Regions
  'BR' AS country_code,
  CASE 
      WHEN id_province = 3665474 THEN 'Acre'
      WHEN id_province = 3408096 THEN 'Alagoas'
      WHEN id_province = 3407762 THEN 'Amapá'
      WHEN id_province = 3665361 THEN 'Amazonas'
      WHEN id_province = 3402362 THEN 'Ceará'
      WHEN id_province = 3463930 THEN 'Espírito Santo'
      WHEN id_province = 3395443 THEN 'Maranhão'
      WHEN id_province = 3457419 THEN 'Mato Grosso'
      WHEN id_province = 3457415 THEN 'Mato Grosso do Sul'
      WHEN id_province = 3457153 THEN 'Minas Gerais'
      WHEN id_province = 3393129 THEN 'Pará'
      WHEN id_province = 3393098 THEN 'Paraíba'
      WHEN id_province = 3392268 THEN 'Pernambuco'
      WHEN id_province = 3392213 THEN 'Piauí'
      WHEN id_province = 3451189 THEN 'Rio de Janeiro'
      WHEN id_province = 3390290 THEN 'Rio Grande do Norte'
      WHEN id_province = 3451133 THEN 'Rio Grande do Sul'
      WHEN id_province = 3924825 THEN 'Rondônia'
      WHEN id_province = 3662560 THEN 'Roraima'
      WHEN id_province = 3448433 THEN 'São Paulo'
      WHEN id_province = 3471168 THEN 'Bahia'
      WHEN id_province = 3450387 THEN 'Santa Catarina'
      WHEN id_province = 3462372 THEN 'Goiás'
      WHEN id_province = 3455077 THEN 'Paraná'
      WHEN id_province = 3447799 THEN 'Sergipe'
      WHEN id_province = 3463575 THEN 'Tocantins'
      WHEN id_province = 3463504 THEN 'Distrito Federal'
    ELSE CAST(NULL AS STRING) 
  END AS state,
  CASE 
      WHEN id_province = 3457153 THEN 'Belo Horizonte'
      WHEN id_province = 3451189 THEN 'Rio de Janeiro'
      WHEN id_province = 3451133 THEN 'Porto Alegre'
      WHEN id_province = 3448433 THEN 'São Paulo'
      WHEN id_province = 3471168 THEN 'Salvador'
      WHEN id_province = 3450387 THEN 'Florianópolis'
      WHEN id_province = 3462372 THEN 'Goiânia'
      WHEN id_province = 3455077 THEN 'Curitiba'
      WHEN id_province = 3463504 THEN 'Brasília'
    ELSE CAST(NULL AS STRING) 
  END AS city, -- not available in the table
  -- Metrics
  clicks,
  CAST(NULL AS BIGINT) AS conversions,
  impressions,
  spend AS total_cost,
  -- Date Reference
  dt_stat AS dt_cost,
  YEAR(dt_stat) AS year,
  MONTH(dt_stat) AS month,
  DAY(dt_stat) AS day
FROM
  datalake_tiktok_campaigns_clean.tiktok_campaigns
WHERE
    CAST(dt_stat AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)