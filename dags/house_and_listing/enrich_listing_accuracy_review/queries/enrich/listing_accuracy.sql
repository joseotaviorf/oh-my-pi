WITH latest_listing_accuracy_ranked AS (
    SELECT
        id_house,
        is_listing_accurate,
        TRUE AS has_3p_access_control,
        ROW_NUMBER() OVER (PARTITION BY id_house ORDER BY dt_change DESC) AS rn
    FROM
        datalake_listing_accuracy_review.listing_accuracy_history
)
SELECT
    id_house,
    is_listing_accurate,
    has_3p_access_control
FROM
    latest_listing_accuracy_ranked
WHERE
    rn = 1
