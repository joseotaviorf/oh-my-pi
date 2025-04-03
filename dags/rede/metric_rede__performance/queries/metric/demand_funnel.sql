SELECT
  CRC32(
    CONCAT(
      CAST(DATE(de.ts_event) AS STRING),
      '|', COALESCE(dc.hubspot_company_name, '1P'),
      '|', COALESCE(cec.event_update, 'Unknown'),
      '|', COALESCE(dc.company_performance_cluster, 'Unknown'),
      '|', COALESCE(dp.id_user_email, 'Unknown'),
      '|', dr.city_name,
      '|', dl.is_high_ticket
    )
  ) AS sk_demand_funnel,
  DATE(de.ts_event) AS dt_date,
  DATE(DATE_TRUNC('WEEK', de.ts_event)) AS dt_week,
  COALESCE(dc.company_name, '1P') AS company_name,
  COALESCE(dc.hubspot_company_name, '1P') AS company_hubspot_name,
  COALESCE(cec.event_update, 'Unknown') AS company_ops_cluster,
  COALESCE(dc.company_performance_cluster, 'Unknown') AS company_performance_cluster,
  COALESCE(dp.id_user_email, 'Unknown') AS account_manager_user,
  dr.city_name,
  dl.is_high_ticket,
  COUNT_IF(et.abbreviation = 'VB') AS visits_booked,
  COUNT_IF(et.abbreviation = 'VC') AS visits_confirmed,
  COUNT_IF(et.abbreviation = 'OS') AS offers_sent,
  COUNT_IF(et.abbreviation = 'OA') AS offers_accepted,
  COUNT_IF(et.abbreviation = 'CCV') AS signed_contract,
  COUNT_IF(et.abbreviation = 'VC') / COUNT_IF(et.abbreviation = 'VB') AS vb2vc,
  COUNT_IF(et.abbreviation = 'OS') / COUNT_IF(et.abbreviation = 'VB') AS vb2os,
  COUNT_IF(et.abbreviation = 'OA') / COUNT_IF(et.abbreviation = 'OS') AS os2oa,
  COUNT_IF(et.abbreviation = 'CCV') / COUNT_IF(et.abbreviation = 'OA') AS oa2ccv,
  COUNT_IF(et.abbreviation = 'CCV') / COUNT_IF(et.abbreviation = 'OS') AS os2ccv,
  COUNT_IF(et.abbreviation = 'CCV') / COUNT_IF(et.abbreviation = 'VB') AS vb2ccv
FROM
  dw_sale.fact_sale_demand_event AS de
LEFT JOIN
  dw_sale.dim_sale_event_type AS et
    ON de.sk_event_type = et.sk_event_type
LEFT JOIN
  dw_sale.dim_listing AS dl
    ON de.sk_house = dl.sk_house
LEFT JOIN
  dw_public.dim_company_rede_partners AS dc
    ON dc.sk_company = de.sk_company_demand
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
GROUP BY ALL