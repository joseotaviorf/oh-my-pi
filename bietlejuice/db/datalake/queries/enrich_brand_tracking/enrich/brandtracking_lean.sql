WITH 
t2 AS (
  SELECT distinct
    id_respondent,
    has_quinto_andar_awareness,
    has_quinto_andar_consideration,
    has_quinto_andar_usage,
    has_quinto_andar_preference,
    has_zap_awareness,
    has_zap_consideration,
    has_zap_usage,
    has_zap_preference,
    has_imovel_web_awareness,
    has_imovel_web_consideration,
    has_imovel_web_usage,
    has_imovel_web_preference,
    has_viva_real_awareness,
    has_viva_real_consideration,
    has_viva_real_usage,
    has_viva_real_preference,
    has_olx_awareness,
    has_olx_consideration,
    has_olx_usage,
    has_olx_preference,
    has_loft_awareness,
    has_loft_consideration,
    has_loft_usage,
    has_loft_preference,
    has_housi_awareness,
    has_housi_consideration,
    has_housi_usage,
    has_housi_preference,
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
  t2.has_quinto_andar_awareness,
  t2.has_quinto_andar_consideration,
  t2.has_quinto_andar_usage,
  t2.has_quinto_andar_preference,
  t2.has_zap_awareness,
  t2.has_zap_consideration,
  t2.has_zap_usage,
  t2.has_zap_preference,
  t2.has_imovel_web_awareness,
  t2.has_imovel_web_consideration,
  t2.has_imovel_web_usage,
  t2.has_imovel_web_preference,
  t2.has_viva_real_awareness,
  t2.has_viva_real_consideration,
  t2.has_viva_real_usage,
  t2.has_viva_real_preference,
  t2.has_olx_awareness,
  t2.has_olx_consideration,
  t2.has_olx_usage,
  t2.has_olx_preference,
  t2.has_loft_awareness,
  t2.has_loft_consideration,
  t2.has_loft_usage,
  t2.has_loft_preference,
  t2.has_housi_awareness,
  t2.has_housi_consideration,
  t2.has_housi_usage,
  t2.has_housi_preference,
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