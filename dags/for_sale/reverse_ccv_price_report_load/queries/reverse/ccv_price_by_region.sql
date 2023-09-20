WITH regions AS (
  SELECT 
    r.sk_region,
    r.name AS neighborhood,
    r.city_group,
    r.city_name,
    CASE 
      /* São Paulo cities */ 
      WHEN r.city_name = 'São Paulo' AND r.name IN('Bela Vista') THEN ARRAY('Bela Vista', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND r.name IN('Água Branca') THEN ARRAY('Água Branca', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND r.name IN('Vila Mariana') THEN ARRAY('Vila Mariana', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND r.name IN('Pinheiros') THEN ARRAY('Pinheiros', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND r.name IN('Jardim Paulista') THEN ARRAY('Jardim Paulista', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND r.name IN('Santa Cecília') THEN ARRAY('Santa Cecília', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND r.name IN('Consolação') THEN ARRAY('Consolação', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND r.name IN('Vila Leopoldina') THEN ARRAY('Vila Leopoldina', '1 specific neighborhood')
      WHEN r.city_name = 'São Paulo' AND c.cluster_name != 'NA.0 - Sem cluster' THEN ARRAY(c.cluster_name, 'neighborhood cluster')
      WHEN r.city_group = 'RMSP' AND r.city_name != 'São Paulo' THEN ARRAY('Grande São Paulo', 'metropolitan area without core city')
      /* Rio de Janeiro cities */ 
      WHEN c.cluster_name IN (
        'RJ.0 - Copacabana, Ipanema, Leblon, Lagoa (+4 bairros)', 
        'RJ.3 - Praia da Bandeira, Ribeira, Pitangueiras, Zumbi', 
        'RJ.5 - Jardim Guanabara, Portuguesa, Urca, Jardim Carioca (+1 bairro)') THEN ARRAY('Rio de Janeiro', 'several neighborhood clusters')
      WHEN c.cluster_name LIKE 'RJ%' THEN ARRAY(c.cluster_name, 'neighborhood cluster')
      WHEN r.city_group IN('Rio de Janeiro') AND r.city_name = 'Rio de Janeiro' THEN ARRAY('Rio de Janeiro Capital', 'defaulting to capital city name')
      WHEN r.city_group IN('Rio de Janeiro') AND r.city_name != 'Rio de Janeiro' THEN ARRAY('Grande Rio de Janeiro', 'metropolitan area without core city')
      /* Porto Alegre cities */ 
      WHEN r.city_group IN('Porto Alegre') AND r.city_name = 'Porto Alegre' THEN ARRAY('Porto Alegre Capital', 'capital city only')
      WHEN r.city_group IN('Porto Alegre') AND r.city_name != 'Porto Alegre' THEN ARRAY('Grande Porto Alegre', 'metropolitan area without core city')
      /* Campinas city */ 
      WHEN r.city_group IN('Campinas') THEN ARRAY('Campinas', 'core city with metropolitan area')
      /* Belo Horizonte cities */ 
      WHEN r.city_group IN('Belo Horizonte') AND r.city_name = 'Belo Horizonte' THEN ARRAY('Belo Horizonte', 'capital city only')
      WHEN r.city_group IN('Belo Horizonte') AND r.city_name != 'Belo Horizonte' THEN ARRAY('Grande Belo Horizonte', 'metropolitan area without core city')
      ELSE ARRAY(r.city_group, 'ELSE city group (defaulting)')
    END AS region_group_array
  FROM 
    dw_public.dim_region AS r
  LEFT JOIN 
    datalake_gsheets_clean.for_sale_marketplace_region_clusters AS c
      ON r.sk_region = c.id_region
  WHERE 
    r.country_name = 'Brazil'
),
unpacking_region_group AS (
  SELECT
    sk_region,
    neighborhood,
    city_name,
    city_group,
    ELEMENT_AT(region_group_array, 1) AS region_group,
    ELEMENT_AT(region_group_array, 2) AS region_group_type
  FROM 
    regions
),
region_display_name AS ( 
  SELECT
    sk_region,
    neighborhood,
    city_name,
    city_group,
    region_group,
    region_group_type,
    CASE
      WHEN region_group_type = '1 specific neighborhood' THEN region_group
      WHEN region_group_type = 'metropolitan area without core city' THEN CONCAT(city_name, ' e região')
      WHEN region_group_type = 'core city with metropolitan area' THEN CONCAT(city_name, ' e região')
      WHEN region_group_type = 'capital city only' THEN city_name
      WHEN region_group_type = 'neighborhood cluster' THEN CONCAT(neighborhood, ' e região')
      WHEN region_group_type = 'several neighborhood clusters' THEN CONCAT(neighborhood, ' e região')
    END AS region_display_name
  FROM 
    unpacking_region_group
),
active_for_sale_city_groups AS (
    SELECT 
      r.city_group,
      COUNT(DISTINCT sk_house) AS listings_publisheds
    FROM 
      dw_sale.fact_listings AS f
    INNER JOIN
      dw_sale.dim_listing AS d
        USING(sk_house)
    INNER JOIN 
      dw_public.dim_region AS r
        USING(sk_region)
    WHERE
      d.status = 'PUBLISHED'
    GROUP BY 
      1
    HAVING 
      listings_publisheds >= 100
),
quintoandar_transactions AS (
  SELECT
    sk_house,
    r.region_group,
    sa.sale_price_agreed / NULLIF(h.total_area, 0) AS price_per_m2,
    DATE(DATE_TRUNC('quarter', sa.ts_sale_agreement_signed)) AS dt_quarter_ccv
  FROM
    dw_sale.fact_offers AS o
  INNER JOIN 
    dw_sale.dim_sale_agreement AS sa
      USING(sk_offer)
  INNER JOIN 
    dw_quintoandar.dim_house AS h
      USING(sk_house)
  INNER JOIN 
    region_display_name AS r 
      USING(sk_region)
  INNER JOIN 
    active_for_sale_city_groups AS c 
      USING(city_group)
  WHERE 
    sa.ts_sale_agreement_signed IS NOT NULL
    AND sa.sale_price_agreed BETWEEN 50000 AND 20000000
),
itbi_transactions AS (
  SELECT 
    t.id_itbi_transaction,
    r.region_group,
    t.declared_transaction_value / NULLIF(t.built_area_m2, 0) AS price_per_m2,
    DATE(DATE_TRUNC('quarter', t.dt_transaction)) AS dt_quarter_ccv
  FROM 
    datalake_open_external_data.itbi_all_residential_transactions AS t
  INNER JOIN 
    region_display_name AS r 
      ON t.id_region = r.sk_region
  INNER JOIN 
    active_for_sale_city_groups AS c 
      ON c.city_group = r.city_group
  WHERE 
    t.property_type IN ('Residencial Horizontal','Residencial Vertical')
    AND t.declared_transaction_value BETWEEN 50000 AND 20000000
),
all_transactions AS (
  SELECT
    sk_house AS id,
    'quintoandar' AS transaction_source,
    region_group,
    price_per_m2,
    dt_quarter_ccv
  FROM 
    quintoandar_transactions
  UNION ALL 
  SELECT
    id_itbi_transaction AS id,
    'itbi' AS transaction_source,
    region_group,
    price_per_m2,
    dt_quarter_ccv
  FROM 
    itbi_transactions
),
transactions_median_prices AS (
  SELECT 
    region_group,
    COUNT(DISTINCT id) AS ccvs,
    APPROX_PERCENTILE(price_per_m2, 0.50) AS median_price_per_m2,
    APPROX_PERCENTILE(IF(transaction_source = 'itbi', price_per_m2, NULL), 0.5) AS itbi_median_price_per_m2,
    APPROX_PERCENTILE(IF(transaction_source = 'quintoandar', price_per_m2, NULL), 0.5) AS quintoandar_median_price_per_m2
  FROM 
    all_transactions
  GROUP BY 
    1
),
itbi_price_factor_to_adjust AS (
  SELECT 
    region_group, 
    ((quintoandar_median_price_per_m2 / itbi_median_price_per_m2) - 1) - (((quintoandar_median_price_per_m2 / itbi_median_price_per_m2) - 1) * 0.15) AS itbi_factor 
  FROM 
    transactions_median_prices 
  WHERE
    itbi_median_price_per_m2 IS NOT NULL
),
all_transactions_adjusted AS (
  SELECT
    id,
    transaction_source,
    region_group,
    IF(transaction_source = 'itbi', (price_per_m2 + (price_per_m2 * itbi_factor)), price_per_m2) AS price_per_m2,
    dt_quarter_ccv
  FROM
    all_transactions AS t
  LEFT JOIN 
    itbi_price_factor_to_adjust AS f
      USING(region_group)
  WHERE
    price_per_m2 < 50000
    AND dt_quarter_ccv >= DATE('2019-01-01')
),
median_price_by_region AS (
  SELECT 
    region_group,
    dt_quarter_ccv,
    ROUND(APPROX_PERCENTILE(price_per_m2, 0.50), 0) as median_price_per_m2
  FROM
    all_transactions_adjusted
  GROUP BY 
    1, 2
),
tabular_data AS (
  SELECT 
    r.sk_region AS id_region,
    r.city_group,
    r.city_name AS city,
    r.neighborhood, 
    region_group AS tier,
    r.region_group_type as tier_type,
    r.region_display_name AS region_used_for_m2_average,
    DATE_FORMAT(p.dt_quarter_ccv, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") AS ccv_period,
    DATE_FORMAT(ADD_MONTHS(p.dt_quarter_ccv, 2), "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") AS ccv_end_period,
    CASE 
      WHEN d.month =  1 THEN 'Mar/' || RIGHT(CAST(d.year AS STRING), 2)
      WHEN d.month =  4 THEN 'Jun/' || RIGHT(CAST(d.year AS STRING), 2)
      WHEN d.month =  7 THEN 'Set/' || RIGHT(CAST(d.year AS STRING), 2)
      WHEN d.month =  10 THEN 'Dez/' || RIGHT(CAST(d.year AS STRING), 2)
    END AS period_name,
    p.median_price_per_m2 AS avg_price_m2
  FROM 
    region_display_name AS r
  LEFT JOIN 
    median_price_by_region AS p
      USING(region_group)
  INNER JOIN 
    dw_public.dim_date AS d
      ON p.dt_quarter_ccv = d.date
  WHERE
    r.sk_region != -1
    AND ADD_MONTHS(p.dt_quarter_ccv, 2) <= DATE_TRUNC('MONTH', CURRENT_DATE)
),
result_format AS (
  SELECT 
      id_region, 
      city_group,
      city,
      neighborhood, 
      tier,
      tier_type,
      region_used_for_m2_average,
      COLLECT_LIST(STRUCT(period_name, ccv_period, ccv_end_period, avg_price_m2)) AS data
  FROM
    tabular_data
  GROUP BY 
      1, 2, 3, 4, 5, 6, 7
)
SELECT 
  CONCAT(UNIX_TIMESTAMP(), LPAD(CAST(ROW_NUMBER() OVER (ORDER BY id_region) AS STRING), 6, '0')) AS id,
  id_region, 
  city_group,
  city,
  neighborhood, 
  tier,
  tier_type,
  region_used_for_m2_average,
  data,
  DATE_FORMAT(CURRENT_TIMESTAMP, "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'") AS ts_load
FROM 
  result_format