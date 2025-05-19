WITH ongoing_listings AS(
  SELECT
    dd.date,
    COALESCE(dc.company_name, '1P') AS company_name,
    COALESCE(dc.hubspot_company_tag, '1P') AS hubspot_company_tag,
    COALESCE(cec.event_update, 'Unknown') AS company_ops_cluster,
    COALESCE(dc.company_performance_cluster, 'Unknown') AS company_performance_cluster,
    COALESCE(dp.id_user_email, 'Unknown') AS account_manager_user,
    dr.city_name,
    dl.is_high_ticket,
    COUNT(ol.sk_house) AS qt_ongoing_listings
  FROM
    dw_sale.fact_daily_ongoing_listing AS ol
  JOIN
    dw_public.dim_date AS dd
      ON dd.sk_date = ol.sk_snapshot_date
  LEFT JOIN
    dw_sale.dim_listing AS dl
      ON ol.sk_house = dl.sk_house
  LEFT JOIN
    dw_public.dim_company_3p_partners AS dc
      ON dc.sk_company = ol.sk_company
  LEFT JOIN
    dw_public.fact_company_events AS cec
      ON cec.sk_company = dc.sk_company
        AND dd.date BETWEEN DATE(cec.ts_start) AND COALESCE(DATE(cec.ts_end), CURRENT_DATE())
        AND cec.sk_company_event_type = 742725214 -- company cluster change event type
  LEFT JOIN
    dw_public.fact_company_events AS ceo
      ON ceo.sk_company = dc.sk_company
        AND dd.date BETWEEN DATE(ceo.ts_start) AND COALESCE(DATE(ceo.ts_end), CURRENT_DATE())
        AND ceo.sk_company_event_type = 210595455 -- company owner change event type
  LEFT JOIN
    dw_public.dim_person AS dp
      ON ceo.event_update = dp.uuid_person
  LEFT JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = ol.sk_region
  GROUP BY
    ALL
),
leads AS (
  SELECT
    DATE(dle.ts_created) AS dt_created,
    COALESCE(dc.company_name, '1P') AS company_name,
    COALESCE(dc.hubspot_company_tag, '1P') AS hubspot_company_tag,
    COALESCE(cec.event_update, 'Unknown') AS company_ops_cluster,
    COALESCE(dc.company_performance_cluster, 'Unknown') AS company_performance_cluster,
    COALESCE(dp.id_user_email, 'Unknown') AS account_manager_user,
    dr.city_name,
    dl.is_high_ticket,
    COUNT(dle.sk_lead_3p) AS qt_leads
  FROM
    dw_rede.dim_lead_3p AS dle
  LEFT JOIN
    dw_rede.fact_lead_3p_flows AS fl
      ON dle.sk_lead_3p = fl.sk_lead_3p
  LEFT JOIN
    dw_sale.dim_listing AS dl
      ON fl.sk_house = dl.sk_house
  LEFT JOIN
    dw_public.dim_company_3p_partners AS dc
      ON dc.sk_company = fl.sk_company
  LEFT JOIN
    dw_public.fact_company_events AS cec
      ON cec.sk_company = dc.sk_company
        AND dle.ts_created BETWEEN cec.ts_start AND COALESCE(cec.ts_end, CURRENT_DATE())
        AND cec.sk_company_event_type = 742725214 -- company cluster change event type
  LEFT JOIN
    dw_public.fact_company_events AS ceo
      ON ceo.sk_company = dc.sk_company
        AND dle.ts_created BETWEEN ceo.ts_start AND COALESCE(ceo.ts_end, CURRENT_DATE())
        AND ceo.sk_company_event_type = 210595455 -- company owner change event type
  LEFT JOIN
    dw_public.dim_person AS dp
      ON ceo.event_update = dp.uuid_person
  LEFT JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = fl.sk_region
  GROUP BY
    ALL
),
first_listing AS (
  SELECT
    DATE(dl.ts_first_publication) AS dt_first_publication,
    COALESCE(dc.company_name, '1P') AS company_name,
    COALESCE(dc.hubspot_company_tag, '1P') AS hubspot_company_tag,
    COALESCE(cec.event_update, 'Unknown') AS company_ops_cluster,
    COALESCE(dc.company_performance_cluster, 'Unknown') AS company_performance_cluster,
    COALESCE(dp.id_user_email, 'Unknown') AS account_manager_user,
    dr.city_name,
    dl.is_high_ticket,
    COUNT(dl.sk_house) AS qt_first_listings
  FROM
    dw_sale.dim_listing AS dl
  LEFT JOIN
    dw_sale.fact_listings AS fl
      ON fl.sk_sale_listing = dl.sk_sale_listing
  LEFT JOIN
    dw_public.dim_company_3p_partners AS dc
      ON dc.sk_company = fl.sk_company
  LEFT JOIN
    dw_public.fact_company_events AS cec
      ON cec.sk_company = dc.sk_company
        AND dl.ts_first_publication BETWEEN cec.ts_start AND COALESCE(cec.ts_end, CURRENT_DATE())
        AND cec.sk_company_event_type = 742725214 -- company cluster change event type
  LEFT JOIN
    dw_public.fact_company_events AS ceo
      ON ceo.sk_company = dc.sk_company
        AND dl.ts_first_publication BETWEEN ceo.ts_start AND COALESCE(ceo.ts_end, CURRENT_DATE())
        AND ceo.sk_company_event_type = 210595455 -- company owner change event type
  LEFT JOIN
    dw_public.dim_person AS dp
      ON ceo.event_update = dp.uuid_person
  LEFT JOIN
    dw_public.dim_region AS dr
      ON dr.sk_region = fl.sk_region
  GROUP BY
    ALL
)
SELECT
  CRC32(
    CONCAT(
      CAST(DATE(de.ts_event) AS STRING),
      '|', COALESCE(dc.hubspot_company_tag, '1P'),
      '|', COALESCE(cec.event_update, 'Unknown'),
      '|', COALESCE(dc.company_performance_cluster, 'Unknown'),
      '|', COALESCE(dp.id_user_email, 'Unknown'),
      '|', dr.city_name,
      '|', dl.is_high_ticket
    )
  ) AS sk_supply_funnel,
  DATE(de.ts_event) AS dt_date,
  DATE(DATE_TRUNC('WEEK', de.ts_event)) AS dt_week,
  COALESCE(dc.company_name, '1P') AS company_name,
  COALESCE(dc.hubspot_company_tag, '1P') AS hubspot_company_tag,
  COALESCE(cec.event_update, 'Unknown') AS company_ops_cluster,
  COALESCE(dc.company_performance_cluster, 'Unknown') AS company_performance_cluster,
  COALESCE(dp.id_user_email, 'Unknown') AS account_manager_user,
  dr.city_name,
  dl.is_high_ticket,
  SUM(ol.qt_ongoing_listings) AS qt_ol,
  SUM(l.qt_leads) AS qt_leads,
  SUM(fl.qt_first_listings) AS qt_first_listings,
  COUNT_IF(et.abbreviation = 'VB') AS qt_vb,
  COUNT_IF(et.abbreviation = 'VC') AS qt_vc,
  COUNT_IF(et.abbreviation = 'OS') AS qt_os,
  COUNT_IF(et.abbreviation = 'OA') AS qt_oa,
  COUNT_IF(et.abbreviation = 'CCV') AS qt_ccv,
  SUM(fl.qt_first_listings) / SUM(l.qt_leads) AS l2fl,
  COUNT_IF(et.abbreviation = 'VC') / COUNT_IF(et.abbreviation = 'VB') AS vb2vc,
  COUNT_IF(et.abbreviation = 'OS') / COUNT_IF(et.abbreviation = 'VB') AS vb2os,
  COUNT_IF(et.abbreviation = 'OA') / COUNT_IF(et.abbreviation = 'OS') AS os2oa,
  COUNT_IF(et.abbreviation = 'CCV') / COUNT_IF(et.abbreviation = 'OA') AS oa2ccv,
  COUNT_IF(et.abbreviation = 'CCV') / COUNT_IF(et.abbreviation = 'OS') AS os2ccv,
  COUNT_IF(et.abbreviation = 'CCV') / COUNT_IF(et.abbreviation = 'VB') AS vb2ccv,
  COUNT_IF(et.abbreviation = 'CCV') / SUM(ol.qt_ongoing_listings) AS ol2ccv
FROM
  dw_sale.fact_sale_demand_event AS de
LEFT JOIN
  dw_sale.dim_sale_event_type AS et
    ON de.sk_event_type = et.sk_event_type
LEFT JOIN
  dw_sale.dim_listing AS dl
    ON de.sk_house = dl.sk_house
LEFT JOIN
  dw_public.dim_company_3p_partners AS dc
    ON dc.sk_company = de.sk_company_supply
    AND de.sk_company_demand = '-1'
LEFT JOIN
  dw_public.fact_company_events AS cec
    ON cec.sk_company = dc.sk_company
    AND de.ts_event BETWEEN cec.ts_start AND COALESCE(cec.ts_end, CURRENT_DATE())
    AND cec.sk_company_event_type = 742725214 -- company cluster change event type
LEFT JOIN
  dw_public.fact_company_events AS ceo
    ON ceo.sk_company = dc.sk_company
    AND de.ts_event BETWEEN ceo.ts_start AND COALESCE(ceo.ts_end, CURRENT_DATE())
    AND ceo.sk_company_event_type = 210595455 -- company owner change event type
LEFT JOIN
  dw_public.dim_person AS dp
    ON ceo.event_update = dp.uuid_person
LEFT JOIN
  dw_public.dim_region AS dr
    ON dr.sk_region = de.sk_region
FULL OUTER JOIN
  ongoing_listings AS ol
    ON DATE(de.ts_event) = ol.date
    AND dc.company_name = ol.company_name
    AND dc.hubspot_company_tag = ol.hubspot_company_tag
    AND cec.event_update = ol.company_ops_cluster
    AND dc.company_performance_cluster = ol.company_performance_cluster
    AND dp.id_user_email = ol.account_manager_user
    AND dr.city_name = ol.city_name
    AND dl.is_high_ticket = ol.is_high_ticket
FULL OUTER JOIN
  leads AS l
    ON DATE(de.ts_event) = l.dt_created
    AND dc.company_name = l.company_name
    AND dc.hubspot_company_tag = l.hubspot_company_tag
    AND cec.event_update = l.company_ops_cluster
    AND dc.company_performance_cluster = l.company_performance_cluster
    AND dp.id_user_email = l.account_manager_user
    AND dr.city_name = l.city_name
    AND dl.is_high_ticket = l.is_high_ticket
FULL OUTER JOIN
  first_listing AS fl
    ON DATE(de.ts_event) = fl.dt_first_publication
    AND dc.company_name = fl.company_name
    AND dc.hubspot_company_tag = fl.hubspot_company_tag
    AND cec.event_update = fl.company_ops_cluster
    AND dc.company_performance_cluster = fl.company_performance_cluster
    AND dp.id_user_email = fl.account_manager_user
    AND dr.city_name = fl.city_name
    AND dl.is_high_ticket = fl.is_high_ticket
GROUP BY ALL