WITH amenities AS (
  SELECT 
    dd.date AS dt_snapshot,
    fhif.sk_house_information_change,
    fhif.sk_house, 
    dhi.value,
    dhi.code,
    CAST(fhif.ts_revision AS DATE) AS dt_started, 
    CAST(fhif.ts_next_revision AS DATE) AS dt_ended
  FROM
    dw_house.fact_house_information_filling AS fhif
  INNER JOIN
    dw_house.dim_house_information AS dhi
      ON fhif.sk_information = dhi.sk_information
  INNER JOIN 
    dw_sale.dim_listing AS dl 
      ON dl.sk_house = fhif.sk_house
  LEFT JOIN 
    dw_public.dim_date AS dd
      ON dd.date BETWEEN CAST(fhif.ts_revision AS DATE) AND COALESCE(CAST(fhif.ts_next_revision AS DATE), CURRENT_DATE)
  WHERE 
    dhi.code IN (
      'VISTA_LIVRE',
      'PISCINA',
      'QUADRA_ESPORTIVA',
      'ACADEMIA',
      'SALAO_DE_FESTAS',
      'SAUNA',
      'LAVANDERIA_NO_PREDIO',
      'GAS_ENCANADO',
      'ESPACO_GOURMET_NA_AREA_COMUM',
      'PERTO_DE_METRO_OU_TREM',
      'BRINQUEDOTECA',
      'VARANDA'
    )
),
ongoing_listing AS ( 
  SELECT 
    ol.sk_house,
    COALESCE(cc.company_name, '1P') AS partner_name,
    COALESCE(cc.company_cluster, '1P') AS company_cluster,
    cc.is_decola_community,
    cc.is_decola_current_cohort,
    d.date AS dt_snapshot
  FROM
    dw_sale.fact_daily_ongoing_listing AS ol 
  LEFT JOIN
    dw_public.dim_date AS d
      ON ol.sk_snapshot_date = d.sk_date
  LEFT JOIN 
    dw_sale.dim_listing AS dl 
      ON dl.sk_house = ol.sk_house
  LEFT JOIN 
    dw_rede.dim_company_cluster AS cc
      ON cc.sk_company_hubspot = dl.sk_company_hubspot
      AND dl.ts_created BETWEEN cc.ts_cluster_start AND COALESCE(cc.ts_cluster_end, CURRENT_DATE)
  WHERE
    d.week_end = d.date
),
join_bases AS (
  SELECT  
    o.dt_snapshot, 
    o.sk_house,
    o.partner_name,
    o.company_cluster,
    o.is_decola_community,
    o.is_decola_current_cohort,
    a.value,
    a.code,
    a.dt_started,
    a.dt_ended
  FROM 
    ongoing_listing AS o
  LEFT JOIN 
    amenities AS a
      ON a.sk_house = o.sk_house 
      AND a.dt_snapshot = o.dt_snapshot
  GROUP BY
    ALL
),
count_amenities AS (
SELECT 
  jb.dt_snapshot,
  jb.partner_name,
  jb.company_cluster,
  jb.is_decola_community,
  jb.is_decola_current_cohort,
  COUNT(DISTINCT jb.sk_house) AS total_houses,
  COUNT(CASE
          WHEN jb.value != 'Unknown' THEN jb.value
        END) AS total_amenities
FROM
  join_bases AS jb 
GROUP BY
  ALL
)
SELECT
  CAST(DATE_TRUNC('week',ca.dt_snapshot) AS DATE) AS dt_week,
  ca.partner_name,
  ca.company_cluster,
  ca.is_decola_community,
  ca.is_decola_current_cohort,
  (ca.total_houses * 12) AS total_amenities_required,
  ca.total_amenities / (ca.total_houses * 12) AS share_completeness
FROM 
  count_amenities AS ca
WHERE
  ca.dt_snapshot IS NOT NULL
GROUP BY
  ALL