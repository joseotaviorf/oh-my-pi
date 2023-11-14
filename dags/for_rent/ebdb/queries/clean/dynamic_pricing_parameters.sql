SELECT
  id,
  name AS parameters_name,
  description AS parameters_description,
  daysThreshold AS days_threshold,
  daysFromAutomaticActivation AS days_from_automatic_activation,
  offersThreshold AS offers_threshold,
  visitsDaysThreshold AS visits_days_threshold,
  visitsthreshold AS visits_threshold,
  dropsCount AS drops,
  initialRentPercentile AS initial_rent_percentile,
  minRentPercentile AS min_rent_percentile,
  initialrentratio AS initial_rent_ratio,
  minrentratio AS min_rent_ratio,
  maximumValuePerReduction AS max_value_per_reduction,
  beginDate AS ts_started,
  endDate AS ts_ended,
  criadoEm AS ts_created,
  atualizadoEm AS ts_updated
FROM 
  datalake_ebdb_raw.dynamicpricingparameters
