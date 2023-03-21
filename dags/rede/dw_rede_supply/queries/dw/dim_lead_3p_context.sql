WITH business_contexts_separated_aux AS (
    SELECT
        EXPLODE(ARRAY('SALE', 'RENT', 'Unknown')) AS business_context,
        ARRAY('FIRST_BATCH', 'FIRST_MONTH_BATCH', 'COMPLEMENTARY', 'RECURRENT', 'N/A') AS recurrency_types
),
recurrency_separated_aux AS (
    SELECT
        business_context,
        EXPLODE(recurrency_types) AS recurrency_type
    FROM
        business_contexts_separated_aux
)
SELECT
    ROW_NUMBER() OVER (PARTITION BY 1 ORDER BY business_context, recurrency_type) AS sk_lead_3p_context,
    business_context,
    recurrency_type,
    business_context = 'SALE' AS is_for_sale,
    business_context = 'RENT' AS is_for_rent,
    recurrency_type = 'FIRST_BATCH' AS is_first_batch,
    recurrency_type = 'FIRST_MONTH_BATCH' AS is_first_month_batch,
    recurrency_type = 'COMPLEMENTARY' AS is_complementary,
    recurrency_type = 'RECURRENT' AS is_recurrent,
    NOW() AS ts_load
FROM
    recurrency_separated_aux