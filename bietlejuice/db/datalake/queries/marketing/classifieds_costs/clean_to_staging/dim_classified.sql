SELECT
  cast(
    CASE source
      WHEN 'Zap Imóveis' THEN 1
      WHEN 'VivaReal' THEN 2
      WHEN 'Mitula' THEN 3
      WHEN 'OLX' THEN 4
      WHEN 'Mercado Livre' THEN 5
      WHEN 'Imovelweb' THEN 6
      WHEN '123i' THEN 7
    END
  as SMALLINT) as sk_classified,
  source as name,
  cast(dt_created as date) as dt_cost,
  current_timestamp as ts_load
FROM datalake_clean.marketing_classifieds_costs
WHERE dt_created  = '{date}' and acc = '{account}'