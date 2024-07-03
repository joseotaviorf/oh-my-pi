SELECT
  TO_DATE(date_month, 'dd/MM/yyyy') AS dt_month,
  CAST(uc_okr_fr_operations AS DECIMAL(10, 4)) AS uc_okr_fr_operations,
  CAST(seamless_journey AS DECIMAL(10, 4)) AS seamless_journey,
  CAST(rent_app_share_of_postcontract AS DECIMAL(10, 4)) AS rent_app_share_post_contract,
  CAST(rent_app_share_of_postcontract_landlord AS DECIMAL(10, 4)) AS rent_app_share_post_contract_landlord,
  CAST(rent_app_share_of_postcontract_tenant AS DECIMAL(10, 4)) AS rent_app_share_post_contract_tenant
FROM
  manual_kpis_polygon