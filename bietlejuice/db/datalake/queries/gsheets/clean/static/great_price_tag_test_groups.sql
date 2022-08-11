SELECT
    CAST(sk_sale_listing AS STRING) AS sk_sale_listing,
    CAST(house_id AS INT) AS id_house,
    CAST(ab_group AS STRING) AS ab_group,
    CAST(country AS STRING) AS country,
    CAST(city_group AS STRING) AS city_group,
    CAST(cidade AS STRING) AS city,
    CAST(bairro AS STRING) AS neighborhood,
    CAST(tipo AS STRING) AS type,
    CAST(price AS INT) AS price,
    CAST(price_bucket AS STRING) AS price_bucket,
    CAST(certainty AS STRING) AS certainty,
    CAST(valor_min AS INT) AS price_min_calculator,
    CAST(valor_max AS INT) AS price_max_calculator,
    CAST(n_quartos AS STRING) AS bedrooms_bucket,
    CAST(range_lpvs_ultimos_30_dias AS STRING) AS range_lpvs_last_30_days
FROM
    datalake_gsheets_raw.great_price_tag_test_groups
