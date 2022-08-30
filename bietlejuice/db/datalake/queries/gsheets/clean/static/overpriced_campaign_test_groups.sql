SELECT
    CAST(sk_house AS INT) AS id_house,
    CAST(sk_user AS INT) AS id_user,
    CAST(email AS STRING) AS email,
    CAST(test_group AS INT) AS test_group,
    CAST(test_group_description AS STRING) AS test_group_description,
    CAST(last_price_before_campaign AS INT) AS last_price_before_campaign,
    CAST(days_without_vb_before_campaign AS INT) AS days_without_vb_before_campaign,
    CAST(p_10 AS INT) AS min_price_calculator,
    CAST(p_90 AS INT) AS max_price_calculator,
    CAST(p_10_adjusted AS INT) AS min_price_calculator_adjusted,
    CAST(p_90_adjusted AS INT) AS max_price_calculator_adjusted,
    CAST(over_calc_range AS STRING) AS overpriced_calculator_range
FROM 
    datalake_gsheets_raw.overpriced_campaign_test_groups