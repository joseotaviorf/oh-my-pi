WITH
  targets AS (
    SELECT
      city_group,
      hub_offer,
      visits_booked,
      visits_completed,
      offers_submitted,
      offers_accepted,
      ccv_signed,
      new_buyer_prospect,
      recovered_buyer_prospect,
      is_rede,
      dt_target,
      '2024_sheet' AS sheet
    FROM
      datalake_gsheets_clean.sale_demand_targets_2024
    UNION ALL
    SELECT
    city_group,
    hub_offer,
    visits_booked,
    visits_completed,
    offers_submitted,
    offers_accepted,
    ccv_signed,
    new_buyer_prospect,
    recovered_buyer_prospect,
    is_rede,
    dt_target,
    'retro_sheet' AS sheet
    FROM
      datalake_gsheets_clean.sale_demand_targets_retro
    UNION ALL
    SELECT
      city_group,
      hub_offer,
      0 AS visits_booked,
      0 AS visits_completed,
      0 AS offers_submitted,
      0 AS offers_accepted,
      0 AS ccv_signed,
      new_buyer_prospect,
      recovered_buyer_prospect,
      is_rede,
      dt_target,
      'bps_sheet' AS sheet
    FROM
      datalake_gsheets_clean.sale_demand_targets_bps_2024
)
SELECT
  t.city_group,
  t.hub_offer,
  t.visits_booked,
  t.visits_completed,
  t.offers_submitted,
  t.offers_accepted,
  t.ccv_signed,
  t.new_buyer_prospect,
  t.recovered_buyer_prospect,
  t.is_rede,
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
