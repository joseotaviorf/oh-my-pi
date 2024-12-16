SELECT
  city_group,
  lead_processing_operation,
  supply_mkt_origin_detailed,
  planning_taxonomy,
  planning_conversion,
  planning_operation,
  planning_cluster,
  company_report_origin,
  prospects,
  qualifieds,
  available_qualifieds,
  opportunities,
  first_listings,
  dt_budget
FROM
  datalake_gsheets_clean.sale_supply_budget_2024
UNION ALL 
SELECT
  city_group,
  NULL AS lead_processing_operation,
  NULL AS supply_mkt_origin_detailed,
  NULL AS planning_taxonomy,
  planning_conversion,
  planning_operation,
  planning_cluster,
  company_report_origin,    
  prospects,
  qualifieds,
  available_qualifieds,
  opportunities,
  first_listings,
  date AS dt_budget
FROM
    datalake_gsheets_clean.sale_supply_budget_2025