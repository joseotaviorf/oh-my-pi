WITH actuals AS (
  SELECT 
    'rent' AS business_context,
    id_house,
    id_tenant_prospect AS id_user,
    MIN(ts_rent_flow_event) AS bc_flow_date

  FROM
    datalake_rent_flows.rent_flows

  WHERE
    DATE(ts_rent_flow_event) < DATE('{load_start_date}') 
    AND DATE(ts_rent_flow_event) >= DATE_SUB(DATE('{load_start_date}'), 1)
    AND country_code = 'BR'
    AND (
      ts_visit_completed IS NOT NULL 
      OR ts_offer_submitted IS NOT NULL
    )

  GROUP BY
    id_house,
    id_tenant_prospect

  UNION ALL

  SELECT
    'sale' AS business_context,
    id_house,
    id_buyer AS id_user,
    MIN(ts_first_event) AS bc_flow_date

  FROM
    datalake_sale_flows.sale_flow

  WHERE
    DATE(ts_first_event) < DATE('{load_start_date}') 
    AND DATE(ts_first_event) >= DATE_SUB(DATE('{load_start_date}'), 1)
    AND (
      ts_first_visit_completed IS NOT NULL 
      OR ts_first_offer_submitted IS NOT NULL
    )

  GROUP BY
    id_house,
    id_buyer

),

house_main AS (

  SELECT
    'rent' AS business_context,
    id,
    neighborhood,
    city,
    type,
    suite_count,
    total_value_per_month AS total_price,
    total_area,
    bathroom_count,
    bedroom_count,
    parking_slots_count,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY timestamp DESC) AS rn
  
  FROM
    wonka.house_main 

  WHERE
    MAKE_DATE(year, month, day) <= DATE('{load_start_date}')
    AND is_for_rent = TRUE

  UNION ALL

  SELECT
    'sale' AS business_context,
    id,
    neighborhood,
    city,
    type,
    suite_count,
    sale_price AS total_price,
    total_area,
    bathroom_count,
    bedroom_count,
    parking_slots_count,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY timestamp DESC) AS rn
  
  FROM
    wonka.house_main 

  WHERE
    MAKE_DATE(year, month, day) <= DATE('{load_start_date}')
    AND is_for_sale = TRUE

),

clusters AS (
  SELECT
    uspc.id AS id_user,
    'rent' AS business_context,
    act.bc_flow_date,
    GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.city') AS cluster_city,
    GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.neighborhoods') AS cluster_neighborhoods,
    CASE 
      WHEN GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.max_price') >= 25000 THEN NULL
      ELSE GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.max_price')
    END AS cluster_max_price,
    GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.qty_bedrooms') AS cluster_qty_bedrooms,
    GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.qty_bathrooms') AS cluster_qty_bathrooms,
    GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.qty_suites') AS cluster_qty_suites,
    GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.perc_pets_friendly') AS cluster_perc_pets_friendly,
    CASE 
      WHEN GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.type') == '{}' THEN NULL 
      ELSE GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.type')
    END AS cluster_type,
    CASE
      WHEN GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.min_area') <= 20 THEN NULL
      ELSE GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.min_area')
    END AS cluster_min_area,
    GET_JSON_OBJECT(uspc.rent_cluster1_user_search_profile, '$.qty_parking') AS cluster_qty_parking,
    ROW_NUMBER() OVER (PARTITION BY uspc.id, act.bc_flow_date ORDER BY uspc.timestamp DESC) AS rn

  FROM 
    wonka.user_search_profile_clustering uspc
  INNER JOIN 
    actuals act
      ON act.id_user=uspc.id
      AND uspc.timestamp < act.bc_flow_date
      AND act.business_context = 'rent'

  WHERE
    MAKE_DATE(uspc.year, uspc.month, uspc.day) < DATE('{load_start_date}')

  UNION ALL

  SELECT
    uspc.id AS id_user,
    'sale' AS business_context,
    act.bc_flow_date,
    GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.city') AS cluster_city,
    GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.neighborhoods') AS cluster_neighborhoods,
    CASE 
      WHEN GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.max_price') >= 20000000 THEN NULL
      ELSE GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.max_price')
    END AS cluster_max_price,
    GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.qty_bedrooms') AS cluster_qty_bedrooms,
    GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.qty_bathrooms') AS cluster_qty_bathrooms,
    GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.qty_suites') AS cluster_qty_suites,
    GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.perc_pets_friendly') AS cluster_perc_pets_friendly,
    CASE 
      WHEN GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.type') == '{}' THEN NULL 
      ELSE GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.type')
    END AS cluster_type,
    CASE
      WHEN GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.min_area') <= 20 THEN NULL
      ELSE GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.min_area')
    END AS cluster_min_area,
    GET_JSON_OBJECT(uspc.sale_cluster1_user_search_profile, '$.qty_parking') AS cluster_qty_parking,
    ROW_NUMBER() OVER (PARTITION BY uspc.id, act.bc_flow_date ORDER BY uspc.timestamp DESC) AS rn

  FROM 
    wonka.user_search_profile_clustering uspc
  INNER JOIN
    actuals act
      ON act.id_user=uspc.id
      AND uspc.timestamp < act.bc_flow_date
      AND act.business_context = 'sale'

  WHERE
    MAKE_DATE(uspc.year, uspc.month, uspc.day) < DATE('{load_start_date}')

),

base AS (
  SELECT
    act.business_context,
    act.id_house,
    act.id_user,
    act.bc_flow_date,
    hm.neighborhood,
    hm.city,
    hm.type,
    hm.suite_count,
    hm.total_price,
    hm.total_area,
    hm.bathroom_count,
    hm.bedroom_count,
    hm.parking_slots_count,
    cl.cluster_city,
    cl.cluster_neighborhoods,
    cl.cluster_max_price,
    cl.cluster_qty_bedrooms,
    cl.cluster_qty_bathrooms,
    cl.cluster_qty_parking,
    cl.cluster_perc_pets_friendly,
    cl.cluster_type,
    cl.cluster_min_area,
    cl.cluster_qty_suites

  FROM 
    actuals act
  LEFT JOIN 
    house_main hm
      ON hm.id=act.id_house
      AND act.business_context=hm.business_context
      AND hm.rn=1 
  LEFT JOIN
    clusters cl 
      ON cl.id_user=act.id_user
      AND act.business_context=cl.business_context
      AND cl.bc_flow_date=act.bc_flow_date
      AND cl.rn=1

  WHERE
    cl.cluster_city IS NOT NULL
)

SELECT
  id_user,
  id_house,
  business_context,
  neighborhood,
  city,
  type,
  suite_count,
  total_price,
  total_area,
  bathroom_count,
  bedroom_count,
  parking_slots_count,
  cluster_city,
  cluster_neighborhoods,
  cluster_max_price,
  cluster_qty_bedrooms,
  cluster_qty_bathrooms,
  cluster_qty_parking,
  cluster_type,
  cluster_min_area,
  cluster_qty_suites,
  CASE
    WHEN cluster_city=city THEN 1
    ELSE 0
  END AS cluster_city_match,
  CASE 
    WHEN ARRAY_CONTAINS(FROM_JSON(cluster_neighborhoods, 'array<string>'), neighborhood) THEN 1
    ELSE 0 
  END AS cluster_neighborhoods_match,
  CASE 
    WHEN total_price = 0 THEN NULL 
    WHEN cluster_max_price >= 20000 AND business_context = 'rent' THEN NULL
    WHEN cluster_max_price >= 20000000 AND business_context = 'sale' THEN NULL
    ELSE ABS(cluster_max_price/1.2 - total_price) / total_price
  END AS cluster_max_price_mape,
  CASE 
    WHEN cluster_qty_bedrooms IS NOT NULL
    AND cluster_qty_bedrooms >= bedroom_count 
    AND cluster_qty_bedrooms <= bedroom_count + 1 THEN 1
    ELSE 0
  END AS cluster_qty_bedrooms_match,
  CASE 
    WHEN cluster_qty_bathrooms IS NOT NULL
    AND cluster_qty_bathrooms >= bathroom_count
    AND cluster_qty_bathrooms <= bathroom_count + 1 THEN 1
    ELSE 0
  END AS cluster_qty_bathrooms_match,
  CASE 
    WHEN cluster_qty_parking IS NOT NULL
    AND cluster_qty_parking >= parking_slots_count
    AND cluster_qty_parking <= parking_slots_count + 1 THEN 1
    ELSE 0
  END AS cluster_qty_parking_match,
  CASE WHEN
  ARRAY_CONTAINS(
    MAP_KEYS(
        MAP_FILTER(
            FROM_JSON(cluster_type, 'map<string,double>'),
            (k, v) -> v > 0.6
        )
    ), type) THEN 1
    ELSE 0
  END AS cluster_type_match,
  CASE 
    WHEN total_area = 0 THEN NULL 
    WHEN cluster_min_area = 20 THEN NULL
    WHEN cluster_min_area = 1000 THEN NULL
    ELSE ABS(cluster_min_area - total_area) / total_area
  END AS cluster_min_area_mape,
  CASE 
    WHEN cluster_qty_suites IS NOT NULL
    AND cluster_qty_suites >= suite_count
    AND cluster_qty_suites <= suite_count + 1 THEN 1
    ELSE 0
  END AS cluster_qty_suites_match,
  bc_flow_date,
  YEAR(bc_flow_date) AS year,
  MONTH(bc_flow_date) AS month,
  DAY(bc_flow_date) AS day

FROM 
  base
