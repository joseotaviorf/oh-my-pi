SELECT DISTINCT
  MD5(
    CONCAT(
      COALESCE(t.step_tag, 'unknown'),
      COALESCE(t.customer_type_tag, 'unknown'),
      COALESCE(t.client_type, 'unknown'),
      COALESCE(t.request_type, 'unknown'),
      COALESCE(t.contact_motivation_tag, 'unknown'),
      COALESCE(t.contact_theme_tag, 'unknown'),
      COALESCE(t.contact_theme_detail_tag, 'unknown')
    )
  ) AS sk_taxonomy,
  COALESCE(t.step_tag, 'unknown') AS step_tag,
  COALESCE(t.customer_type_tag, 'unknown') AS customer_type_tag,
  COALESCE(t.client_type, 'unknown') AS customer_type,
  COALESCE(t.request_type, 'unknown') AS request_type,
  COALESCE(t.contact_motivation_tag, 'unknown') AS motivation,
  COALESCE(t.contact_theme_tag, 'unknown') AS theme,
  COALESCE(t.contact_theme_detail_tag, 'unknown') AS theme_detail,
  tr.journey,
  tr.sub_journey,
  tr.line_owner,
  NOW() AS ts_load
FROM
  datalake_customer_support.tickets AS t
LEFT JOIN
  datalake_gsheets_clean.ticket_rate_classification AS tr
    ON t.contact_theme_detail_tag = tr.micro_taxonomy
      AND t.contact_theme_tag = tr.macro_taxonomy
