WITH week_ongoing_base AS (  
  SELECT 
    dd.week_start AS week,
    COALESCE(cc.company_name, '1P') AS partner_name,
    COALESCE(cc.company_cluster, '1P') AS company_cluster,
    cc.is_decola_community,
    cc.is_decola_current_cohort,
    COUNT(DISTINCT ol.sk_house) AS total_houses
  FROM 
    dw_sale.fact_daily_ongoing_listing AS ol
  LEFT JOIN 
    dw_public.dim_date AS dd
      ON dd.sk_date = ol.sk_snapshot_date
  LEFT JOIN
    dw_sale.dim_listing AS dl
      ON dl.sk_house = ol.sk_house
  LEFT JOIN 
    dw_rede.dim_company_cluster AS cc
      ON cc.sk_company_hubspot = dl.sk_company_hubspot
      AND dl.ts_created BETWEEN cc.ts_cluster_start AND COALESCE(cc.ts_cluster_end, CURRENT_DATE)
  GROUP BY
    ALL
),
week_offer_base AS (
  SELECT 
    CAST(DATE_TRUNC('week', FROM_UTC_TIMESTAMP(fo.ts_offer_dismissed, 'GMT-3')) AS DATE) AS week, 
    COALESCE(cc.company_name, '1P') AS partner_name,
    COALESCE(cc.company_cluster, '1P') AS company_cluster,
    cc.is_decola_community,
    cc.is_decola_current_cohort,
    COUNT(DISTINCT 
          CASE
            WHEN fo.ts_offer_dismissed IS NOT NULL THEN fo.sk_offer
          END) AS total_offers_dismissed
  FROM
    dw_sale.fact_offers AS fo
  LEFT JOIN
    dw_sale.dim_listing AS dl
      ON dl.sk_house = fo.sk_house
  LEFT JOIN 
    dw_rede.dim_company_cluster AS cc
      ON cc.sk_company_hubspot = dl.sk_company_hubspot
      AND dl.ts_created BETWEEN cc.ts_cluster_start AND COALESCE(cc.ts_cluster_end, CURRENT_DATE)
  WHERE
    fo.ts_offer_dismissed IS NOT NULL 
  GROUP BY
    ALL
),
week_ccv_base AS (
  SELECT 
    CAST(DATE_TRUNC('week', FROM_UTC_TIMESTAMP(fo.ts_sale_agreement_signed, 'GMT-3')) AS DATE) AS week, 
    COALESCE(cc.company_name, '1P') AS partner_name,
    COALESCE(cc.company_cluster, '1P') AS company_cluster,
    cc.is_decola_community,
    cc.is_decola_current_cohort,
    COUNT(DISTINCT 
          CASE
            WHEN fo.ts_sale_agreement_signed IS NOT NULL THEN fo.sk_offer
          END) AS total_ccvs_signed
  FROM 
    dw_sale.fact_offers AS fo
  LEFT JOIN
    dw_sale.dim_listing AS dl
      ON dl.sk_house = fo.sk_house
  LEFT JOIN 
    dw_rede.dim_company_cluster AS cc
      ON cc.sk_company_hubspot = dl.sk_company_hubspot
      AND dl.ts_created BETWEEN cc.ts_cluster_start AND COALESCE(cc.ts_cluster_end, CURRENT_DATE)
  WHERE
    fo.ts_sale_agreement_signed IS NOT NULL
  GROUP BY
    ALL
),
union_base AS ( 
  SELECT 
    ob.week, 
    ob.partner_name,
    ob.company_cluster,
    ob.is_decola_community,
    ob.is_decola_current_cohort,
    ob.total_houses,
    COALESCE(of.total_offers_dismissed,0) AS total_offers_dismissed,
    COALESCE(ccv.total_ccvs_signed,0) AS total_ccvs_signed
  FROM 
    week_ongoing_base AS ob
  LEFT JOIN 
    week_offer_base AS of
      ON ob.week = of.week
      AND ob.partner_name = of.partner_name
      AND ob.company_cluster = of.company_cluster
      AND ob.is_decola_community = of.is_decola_community
      AND ob.is_decola_current_cohort = of.is_decola_current_cohort
  LEFT JOIN 
    week_ccv_base AS ccv
      ON ob.week = ccv.week
      AND ob.partner_name = ccv.partner_name
      AND ob.company_cluster = ccv.company_cluster
      AND ob.is_decola_community = ccv.is_decola_community
      AND ob.is_decola_current_cohort = ccv.is_decola_current_cohort
)
SELECT 
  f.week AS dt_week,
  f.partner_name,
  f.company_cluster,
  f.is_decola_community,
  f.is_decola_current_cohort,
  f.total_offers_dismissed,
  f.total_ccvs_signed,
  SUM(COALESCE(f2.total_offers_dismissed, 0)) AS total_offers_dismissed_last_3_week,
  SUM(COALESCE(f2.total_ccvs_signed, 0)) AS total_ccvs_signed_last_3_week,
  SUM(COALESCE(f2.total_ccvs_signed, 0)) / (SUM(COALESCE(f2.total_offers_dismissed, 0)) + SUM(COALESCE(f2.total_ccvs_signed, 0))) AS share_offers
FROM
  union_base f
LEFT JOIN
  union_base f2
    ON f2.partner_name = f.partner_name
    AND f2.week BETWEEN DATE_ADD(f.week, -14 ) AND f.week
GROUP BY
  ALL