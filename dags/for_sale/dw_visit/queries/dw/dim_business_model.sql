SELECT
    1 AS sk_business_model,
    'BM_1P' AS business_model,
    NOW() AS ts_load
UNION ALL
SELECT
    2 AS sk_business_model,
    'BM_3P_DEMAND_1P_SUPPLY' AS business_model,
    NOW() AS ts_load
UNION ALL
SELECT
    3 AS sk_business_model,
    'BM_3P_DEMAND_3P_SUPPLY_6P' AS business_model,
    NOW() AS ts_load
    UNION ALL
SELECT
    4 AS sk_business_model,
    'BM_3P_LEAD_GEN_1P_SUPPLY' AS business_model,
    NOW() AS ts_load
    UNION ALL
SELECT
    5 AS sk_business_model,
    'BM_3P_LEAD_GEN_3P_SUPPLY' AS business_model,
    NOW() AS ts_load
    UNION ALL
SELECT
    6 AS sk_business_model,
    'BM_3P_SUPPLY_1P_DEMAND_AGENT' AS business_model,
    NOW() AS ts_load
    UNION ALL
SELECT
    7 AS sk_business_model,
    'BM_ERROR' AS business_model,
    NOW() AS ts_load
