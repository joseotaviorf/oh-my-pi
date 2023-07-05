SELECT DISTINCT
  id_partner AS sk_partner,
  id_admin_user AS sk_admin_user,
  id_franchise AS sk_franchise,
  id_registration_user AS sk_registration_user,
  partner_name,
  wallet,
  ts_registration,
  ts_inactive_user,
  NOW()       AS ts_load
FROM datalake_atta_clean.partner_info
