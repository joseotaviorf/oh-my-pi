SELECT DISTINCT
  id_partner AS sk_partner,
  id_admin_user AS sk_admin_user,
  id_franchise AS sk_franchise,
  id_registration_user AS sk_registration_user,
  partner_name,
  CASE
    WHEN partner_name LIKE 'Franquia%' THEN 'FRANCHISE'
    WHEN partner_name LIKE '%Hub%'
       OR partner_name LIKE 'Carteira%'
       OR partner_name LIKE '5A HUB%'
       OR LOWER(partner_name) LIKE '5a >>%'
       OR partner_name IS NULL THEN 'INTERNAL'
    ELSE 'EXTERNAL'
  END AS partner_type,
  wallet,
  ts_registration,
  ts_inactive_user,
  NOW()       AS ts_load
FROM 
  datalake_atta.partner_info
