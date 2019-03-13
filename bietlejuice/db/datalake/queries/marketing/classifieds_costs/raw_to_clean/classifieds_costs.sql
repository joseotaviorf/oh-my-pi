SELECT
  "source",
  "cost"
FROM datalake_raw.marketing_classifieds_costs
WHERE dt = '{date}' and acc = '{account}'