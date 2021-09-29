WITH 
t2 AS (
  SELECT distinct
    id_respondent,
    quinto_andar_awareness,
    quinto_andar_consideration,
    quinto_andar_usage,
    quinto_andar_preference,
    zap_awareness,
    zap_consideration,
    zap_usage,
    zap_preference,
    imovel_web_awareness,
    imovel_web_consideration,
    imovel_web_usage,
    imovel_web_preference,
    viva_real_awareness,
    viva_real_consideration,
    viva_real_usage,
    viva_real_preference,
    olx_awareness,
    olx_consideration,
    olx_usage,
    olx_preference,
    loft_awareness,
    loft_consideration,
    loft_usage,
    loft_preference,
    housi_awareness,
    housi_consideration,
    housi_usage,
    housi_preference,
    year,
    quarter
  FROM 
    datalake_brand_tracking.brandtracking_full
  WHERE
    year = {year_previous_quarter}
    AND quarter = {previous_quarter}
)
SELECT
  t1.id_respondent as id_respondent,
  t1.market as market,
  t1.region as region,
  t1.wave as wave,
  t1.city as city,
  t1.state as state,
  t1.gender as gender,
  t1.age as age,
  t1.income as income,
  t1.civil_status as civil_status,
  t1.target as target,
  t2.quinto_andar_awareness,
  t2.quinto_andar_consideration,
  t2.quinto_andar_usage,
  t2.quinto_andar_preference,
  t2.zap_awareness,
  t2.zap_consideration,
  t2.zap_usage,
  t2.zap_preference,
  t2.imovel_web_awareness,
  t2.imovel_web_consideration,
  t2.imovel_web_usage,
  t2.imovel_web_preference,
  t2.viva_real_awareness,
  t2.viva_real_consideration,
  t2.viva_real_usage,
  t2.viva_real_preference,
  t2.olx_awareness,
  t2.olx_consideration,
  t2.olx_usage,
  t2.olx_preference,
  t2.loft_awareness,
  t2.loft_consideration,
  t2.loft_usage,
  t2.loft_preference,
  t2.housi_awareness,
  t2.housi_consideration,
  t2.housi_usage,
  t2.housi_preference,
  t1.year as year,
  t1.quarter as quarter
FROM 
  datalake_brand_tracking_clean.brandtracking t1
LEFT JOIN
  t2
ON
  t1.id_respondent = t2.id_respondent and
  t1.year = t2.year and
  t1.quarter = t2.quarter
WHERE
  t1.year = {year_previous_quarter}
  AND t1.quarter = {previous_quarter}