SELECT DISTINCT
  COALESCE(id_franchise,-1) AS sk_franchise,
  COALESCE(id_registration_user,-1) AS sk_registration_user,
  COALESCE(id_franchise_status,-1) AS sk_franchise_status,
  franchise_category    AS sk_franchise_category,
  franchise_type        AS sk_franchise_type,
  franchise_name,
  CASE
        WHEN franchise_category = 1 THEN 'EXPERT'
        WHEN franchise_category = 0 THEN 'START'
    END                 AS franchise_category,
  royalties_percentage_value,
  martketing_fund_percentage,
  grace_period_royalties,
  grace_period_tec,
  ts_contract_deadline,
  ts_registration,
  ts_franchise_signature,
    NOW()       AS ts_load
FROM
  datalake_atta_clean.franchise_info
