WITH taxonomy AS (
  SELECT 
    MD5(
      CONCAT(
        COALESCE(step_tag, ''),
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, ''),
        COALESCE(contact_theme_detail_tag, '')
      )
    ) AS sk_taxonomy, 
    client_type AS customer_type,
    step_tag,
    customer_type_tag,
    request_type,
    contact_motivation_tag AS motivation,
    contact_theme_tag AS theme,
    contact_theme_detail_tag AS theme_detail,
    NOW() AS ts_load
  FROM 
    datalake_customer_support.tickets
)
SELECT DISTINCT
  tax.sk_taxonomy,
  tax.customer_type,
  tax.step_tag,
  tax.customer_type_tag,
  tax.request_type,
  tax.motivation,
  tax.theme,
  tax.theme_detail,
  tr.journey,
  tr.sub_journey,
  tr.line_owner,
  tax.ts_load
FROM
  taxonomy AS tax
LEFT JOIN
  datalake_gsheets_clean.ticket_rate_classification AS tr
    ON tax.theme_detail = tr.micro_taxonomy
      AND tax.theme = tr.macro_taxonomy