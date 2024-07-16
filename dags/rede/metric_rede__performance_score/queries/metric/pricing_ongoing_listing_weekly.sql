WITH calculator_at_time AS (
  SELECT 
    ol.sk_house,
    d.week_start,
    ol.sk_snapshot_date,
    dl.ts_first_publication,
    CASE 
      WHEN ol.sale_price > pc.price_p_70 THEN 'sale price > P70'
      WHEN ol.sale_price <= pc.price_p_70 THEN 'sale price <= P70'
    END AS p_70_type,
    COALESCE(cc.company_name, '1P') AS partner_name,
    COALESCE(cc.company_cluster, '1P') AS company_cluster,
    cc.is_decola_community,
    cc.is_decola_current_cohort
  FROM
    dw_sale.fact_daily_ongoing_listing AS ol
  LEFT JOIN
    dw_public.dim_date AS d
      ON ol.sk_snapshot_date = d.sk_date
  LEFT JOIN
    dw_house.dim_house_price_calculator_revision AS pc
      ON pc.id_house = ol.sk_house
      AND d.date BETWEEN pc.dt_revision_started AND pc.dt_revision_ended
  LEFT JOIN 
    dw_sale.dim_listing AS dl
      ON dl.sk_house = ol.sk_house
  LEFT JOIN 
    dw_rede.dim_company_cluster AS cc
      ON cc.sk_company_hubspot = dl.sk_company_hubspot
      AND dl.ts_created BETWEEN cc.ts_cluster_start AND COALESCE(cc.ts_cluster_end, CURRENT_DATE)
)
SELECT 
  CAST(DATE_TRUNC('week',d.date) AS DATE) AS dt_week,
  c.partner_name,
  c.company_cluster,
  c.is_decola_community,
  c.is_decola_current_cohort,
  COUNT(DISTINCT c.sk_house) AS total_listings,
  COUNT(DISTINCT 
        CASE
          WHEN p_70_type = 'sale price <= P70' THEN sk_house
        END) AS total_listings_less_p70,
  COUNT(DISTINCT
        CASE
          WHEN p_70_type = 'sale price <= P70' THEN sk_house
        END) / COUNT(DISTINCT c.sk_house) as share_total_listings_less_p70
FROM
  calculator_at_time AS c
LEFT JOIN
  dw_public.dim_date AS d
    ON c.sk_snapshot_date = d.sk_date
WHERE
  c.p_70_type IS NOT NULL
GROUP BY
  ALL