WITH 
base_rent AS (
  SELECT DISTINCT
    id_house, 
    prediction, 
    MAX(DATE(timestamp_available)) OVER() AS dt_max_snapshot, 
    DATE(timestamp_available) AS dt_snapshot
  FROM 
    datalake_demand_balancer_service_clean.demand_balancer
  WHERE
    model_version = 'maestro-V1'
),
score_rent AS (
  SELECT DISTINCT
    id_house AS sk_house,
    prediction AS classified_score_rent
  FROM 
    base_rent
  WHERE 
    dt_max_snapshot = dt_snapshot
),
base_sale AS (
  SELECT DISTINCT
    ps.sk_house, 
    dr.city_name, 
    ps.liquidity_score, 
    ps.funnel_score, 
    MAX(ps.date_snapshot) OVER() AS max_dt_snapshot, 
    ps.date_snapshot AS dt_snapshot
  FROM 
    sales_liquidity_score.predicted_scores AS ps 
  LEFT JOIN 
    datalake_ebdb_listing.house AS h 
      ON h.id = ps.sk_house
  LEFT JOIN 
    dw_public.dim_region AS dr 
      ON dr.sk_region = h.id_region
  GROUP BY ALL
), 
refined_base_sale AS (
  SELECT DISTINCT
    sk_house, 
    liquidity_score, 
    funnel_score, 
    city_name,
    PERCENTILE_CONT(0.1) WITHIN GROUP (ORDER BY funnel_score ASC) OVER(PARTITION BY city_name) AS threshold
  FROM 
    base_sale AS b 
  WHERE 
     b.dt_snapshot = b.max_dt_snapshot
  GROUP BY ALL
),
score_sale AS (
  SELECT DISTINCT
    sk_house,
    CASE 
      WHEN funnel_score >= threshold THEN liquidity_score * (100 - funnel_score) 
      WHEN funnel_score < threshold THEN liquidity_score * (100 - funnel_score) * funnel_score/threshold
      ELSE 0
    END AS classified_score_sale
  FROM 
    refined_base_sale
)
SELECT
  COALESCE(sr.sk_house, ss.sk_house) AS sk_house,
  classified_score_rent,
  classified_score_sale,
  CURRENT_DATE AS dt_snapshot
FROM 
  score_rent AS sr 
FULL OUTER JOIN 
  score_sale AS ss
    ON sr.sk_house = ss.sk_house
