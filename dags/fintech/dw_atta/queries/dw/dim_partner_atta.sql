SELECT DISTINCT
  COALESCE(id_partner,-1) AS sk_partner,
  COALESCE(id_admin_user,-1) AS sk_admin_user,
  COALESCE(id_franchise,-1) AS sk_franchise,
  COALESCE(id_registration_user,-1) AS sk_registration_user,
  partner_name,
  CASE
        WHEN REPLACE(LOWER(partner_name), ' ') LIKE '%5a>>atta%'    THEN 'QuintoAndar Full Atta'
        WHEN REPLACE(LOWER(partner_name), ' ') LIKE '%5a%'          THEN 'QuintoAndar Backlog'
        WHEN LOWER(partner_name) LIKE '%casa mineira%'              THEN 'Casa Mineira'
        ELSE 'Other partnerships'
  END AS wallet,
  ts_registration,
  ts_inactive_user
FROM datalake_atta_clean.partner_info
