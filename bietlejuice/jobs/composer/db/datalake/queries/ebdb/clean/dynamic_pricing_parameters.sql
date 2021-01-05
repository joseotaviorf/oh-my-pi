select
  id,
  name as parameters_name,
  description AS parameters_description,
  daysThreshold as days_threshold,
  offersThreshold as offers_threshold,
  visitsDaysThreshold as visits_days_threshold,
  visitsthreshold as visits_threshold,
  dropsCount as drops,
  beginDate as ts_started,
  endDate as ts_ended,
  criadoEm as ts_created,
  atualizadoEm as ts_updated,
  initialRentPercentile as initial_rent_percentile,
  minRentPercentile as min_rent_percentile,
  initialrentratio as initial_rent_ratio,
  minrentratio as min_rent_ratio
from datalake_ebdb_raw.dynamicpricingparameters
