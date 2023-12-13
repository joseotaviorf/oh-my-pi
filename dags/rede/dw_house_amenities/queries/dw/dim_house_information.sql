WITH exploded_amenities AS (
    SELECT
        id_amenity,
        CASE
            WHEN is_condo_amenity THEN 'CONDO_AMENITY'
            ELSE 'HOUSE_AMENITY'
        END AS information_type,
        EXPLODE(ARRAY('TRUE', 'FALSE', 'Unknown')) AS value,
        code,
        name,
        slug,
        CASE
            WHEN NOT is_active 
                OR DATEDIFF(CURRENT_DATE, ts_last_usage) > 365
                THEN 'DEPRECATED'
            WHEN ratio_houses_filled < 0.5 THEN 'UNCOMMON'
            ELSE 'COMMON'
        END AS usage_frequency,
        CASE
            WHEN ratio_houses_true < 0.1 THEN 'UNCOMMON'
            ELSE 'COMMON'
        END AS true_value_frequency,
        ratio_houses_filled,
        ratio_sale_houses_filled,
        ratio_rent_houses_filled,
        ratio_houses_true,
        ratio_sale_houses_true,
        ratio_rent_houses_true,
        is_condo_amenity,
        ts_first_usage,
        ts_last_usage
    FROM
        datalake_ebdb_amenities.amenity
)
SELECT
    (id_amenity || is_condo_amenity::INT || IF(value = 'Unknown', 2, (value='TRUE')::INT))::INT AS sk_information,
    id_amenity,
    information_type,
    value,
    code,
    name,
    slug,
    usage_frequency,
    true_value_frequency,
    ratio_houses_filled AS ratio_houses_with_known_value,
    ratio_sale_houses_filled AS ratio_sale_houses_with_known_value,
    ratio_rent_houses_filled AS ratio_rent_houses_with_known_value,
    ratio_houses_true AS ratio_houses_with_true_value,
    ratio_sale_houses_true AS ratio_sale_houses_with_true_value,
    ratio_rent_houses_true AS ratio_rent_houses_with_true_value,
    usage_frequency = 'DEPRECATED' AS is_deprecated,
    is_condo_amenity,
    ts_first_usage,
    ts_last_usage,
    NOW() AS ts_load
FROM
    exploded_amenities
