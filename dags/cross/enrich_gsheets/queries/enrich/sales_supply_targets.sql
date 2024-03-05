WITH
  targets AS (
    SELECT
      city_group,
      lead_processing_operation,
      supply_mkt_origin_detailed,
      planning_taxonomy,
      prospects,
      qualifieds,
      opportunities,
      available_qualifieds,
      first_listings,
      dt_target,
      '2024_sheet' AS sheet
    FROM
      datalake_gsheets_clean.sale_supply_targets_2024
    UNION ALL
    SELECT
    city_group,
    lead_processing_operation,
    supply_mkt_origin_detailed,
    planning_taxonomy,
    prospects,
    qualifieds,
    opportunities,
    available_qualifieds,
    first_listings,
    dt_target,
    'retro_sheet' AS sheet
    FROM
      datalake_gsheets_clean.sale_supply_targets_retro
)
SELECT
  t.city_group,
  t.lead_processing_operation,
  t.supply_mkt_origin_detailed,
  t.planning_taxonomy,
  t.prospects,
  t.qualifieds,
  t.opportunities,
  t.available_qualifieds,
  t.first_listings,
  t.sheet,
  dd.year,
  dd.month,
  dd.day,
  dd.quarter,
  dd.week_start,
  t.dt_target
FROM
  targets AS t
INNER JOIN
  datalake_quintoandar.aux_date AS dd
    ON t.dt_target = dd.`date`
