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
),
count_listings AS (
  SELECT 
    c.week_start AS week,
    c.partner_name,
    c.company_cluster,
    c.is_decola_community,
    c.is_decola_current_cohort,
    COUNT(DISTINCT c.sk_house) AS total_first_listings,
    COUNT(DISTINCT
          CASE
            WHEN c.p_70_type = 'sale price <= P70' THEN c.sk_house
          END) AS total_first_listings_less_p70
  FROM 
    calculator_at_time AS c
  LEFT JOIN
    dw_public.dim_date AS d
      ON c.sk_snapshot_date = d.sk_date
  WHERE 
    d.date = CAST(c.ts_first_publication AS DATE)
      AND c.p_70_type IS NOT NULL
  GROUP BY
    ALL
)
SELECT
  cl.week AS dt_week,
  cl.partner_name,
  cl.company_cluster,
  cl.is_decola_community,
  cl.is_decola_current_cohort,
  SUM(cl2.total_first_listings) AS total_first_listings,
  SUM(cl2.total_first_listings_less_p70) AS total_first_listings_less_p70,
  SUM(cl2.total_first_listings_less_p70)/ SUM(cl2.total_first_listings) AS share_total_first_listings_less_p70
FROM
  count_listings AS cl
LEFT JOIN
  count_listings AS cl2
    ON cl.partner_name = cl2.partner_name
    AND cl.company_cluster = cl2.company_cluster
    AND cl2.week BETWEEN DATE_ADD(cl.week, -14) AND cl.week
GROUP BY
  ALL