-- Reverse table rent_liquidity_score in reverse_rent_liquidity_score (written by reverse_rent_liquidity_score_load).
-- SQS export is reverse_rent_liquidity_score_access (MasterfeedHouseRentLiquidityScore).
-- One row per fact row; id_house is houseId in the JSON payload.
--
-- Source dw_liquidity.fact_house_rent_liquidity: house_liquidity_score is the metric in column
-- rent_liquidity_score — the probability that a house will be rented within 4 weeks after publication.
SELECT
  fhl.sk_house AS id_house,
  fhl.rent_liquidity_model_version,
  fhl.rent_liquidity_score,
  CURRENT_DATE AS dt_snapshot
FROM
  dw_liquidity.fact_house_rent_liquidity AS fhl
