WITH taxonomy AS (
  SELECT 
    MD5(
      CONCAT(
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, '')
      )
    ) AS sk_taxonomy, 
    client_type AS customer_type,
    customer_type_tag,
    request_type,
    contact_motivation_tag AS motivation,
    contact_theme_tag AS theme,
    NOW() AS ts_load
  FROM 
    datalake_customer_support.chat
  UNION ALL
  SELECT 
    MD5(
      CONCAT(
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, '')
      )
    ) AS sk_taxonomy, 
    client_type AS customer_type,
    customer_type_tag,
    request_type,
    contact_motivation_tag AS motivation,
    contact_theme_tag AS theme,
    NOW() AS ts_load
  FROM 
    datalake_customer_support.call
  UNION ALL
  SELECT 
    MD5(
      CONCAT(
        COALESCE(customer_type_tag, ''),
        COALESCE(client_type, ''),
        COALESCE(request_type, ''),
        COALESCE(contact_motivation_tag, ''),
        COALESCE(contact_theme_tag, '')
      )
    ) AS sk_taxonomy, 
    client_type AS customer_type,
    customer_type_tag,
    request_type,
    contact_motivation_tag AS motivation,
    contact_theme_tag AS theme,
    NOW() AS ts_load
  FROM 
    datalake_customer_support.email
)
SELECT DISTINCT
  *
FROM
  taxonomy