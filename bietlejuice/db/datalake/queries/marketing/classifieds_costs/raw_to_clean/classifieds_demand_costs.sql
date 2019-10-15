SELECT
  medium,
  source,
  replace(cost, ',', '') as cost
FROM datalake_raw.marketing_demand_classifieds_costs
WHERE dt = '{date}' and acc = '{account}'