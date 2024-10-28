WITH rent_status_version_order AS (
    SELECT
        id_house,
        id_house_listing,
        MIN(ts_status_started) AS ts_status_started,
        MAX(ts_status_ended) AS ts_status_ended
    FROM
        datalake_ebdb_listing.house_listing_status
    GROUP BY
        1, 2
),
calculator_changes AS (
    SELECT
        hpp_aud.id_house,
        hpp_aud.rev AS id_revision,
        hpp_aud.business_context,
        hpp_aud.p_10,
        hpp_aud.p_30,
        hpp_aud.p_50,
        hpp_aud.p_70,
        hpp_aud.p_90,
        hpp_aud.certainty,
        r.ts_revision AS ts_calculator_result_started,
        LEAD(r.ts_revision) OVER (PARTITION BY id_house, business_context ORDER BY r.ts_revision) AS ts_calculator_result_ended
    FROM
        datalake_ebdb_clean.house_predicted_price_aud AS hpp_aud
    INNER JOIN
        datalake_ebdb_user.user_revision_entity AS r
            ON hpp_aud.rev = r.id
)
SELECT
    cc.id_house,
    IF(cc.business_context = 'SALE', NULL, rls.id_house_listing) AS id_house_listing,
    cc.id_revision,
    cc.business_context,
    cc.p_10 AS calculator_min_price,
    cc.p_30 AS calculator_p30_price,
    cc.p_50 AS calculator_price,
    cc.p_70 AS calculator_p70_price,
    cc.p_90 AS calculator_max_price,
    cc.certainty AS calculator_certainty,
    cc.ts_calculator_result_started,
    cc.ts_calculator_result_ended
FROM
    calculator_changes AS cc
LEFT JOIN
    rent_status_version_order AS rls
        ON rls.id_house = cc.id_house
        AND cc.ts_calculator_result_started BETWEEN rls.ts_status_started AND COALESCE(rls.ts_status_ended, TO_TIMESTAMP(CURRENT_DATE))
