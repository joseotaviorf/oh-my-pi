SELECT
  ce.id_event AS sk_company_event,
  et.sk_company_event_type,
  ce.sk_company,
  ce.event_update,
  ce.is_current_cohort,
  ce.ts_start,
  ce.ts_end,
  NOW() AS ts_load
FROM
  datalake_hubspot.company_events AS ce
LEFT JOIN
  dw_public.dim_company_event_type AS et
    ON ce.event_type = et.event_type
    AND ce.event_source = et.event_source