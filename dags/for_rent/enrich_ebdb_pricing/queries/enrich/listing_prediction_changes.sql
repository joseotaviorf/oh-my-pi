WITH rent_status_version_order AS (
    SELECT DISTINCT
        hl.id_house,
        hl.id_house_listing,
        hl.ts_listing_version_start,
        hl.ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing AS hl
    INNER JOIN
        datalake_ebdb_listing.business_context_history AS bch
            ON hl.id_house = bch.id_house
            AND hl.ts_listing_version_start <= bch.ts_state_started
            AND COALESCE(bch.ts_state_ended, CURRENT_TIMESTAMP) <= COALESCE(hl.ts_listing_version_end, CURRENT_TIMESTAMP)
    WHERE
        bch.business_context = 'RENT'
        AND hl.id_house_listing IS NOT NULL
),
sale_timestamp_version AS (
  SELECT
    id_house,
    id_sale_listing,
    ts_status_started,
    ts_status_ended,
    ROW_NUMBER() OVER(PARTITION BY id_sale_listing ORDER BY ts_status_started ASC) AS rn_start,
    ROW_NUMBER() OVER(PARTITION BY id_sale_listing ORDER BY COALESCE(ts_status_ended, CURRENT_TIMESTAMP) DESC) AS rn_end
  FROM
    datalake_sale_listings.sale_listing_status
),
sale_status_version_order AS (
  SELECT
    stv1.id_house,
    stv1.id_sale_listing AS id_house_listing,
    stv1.ts_status_started AS ts_listing_version_start,
    stv2.ts_status_ended AS ts_listing_version_end
  FROM
    sale_timestamp_version AS stv1
  INNER JOIN
    sale_timestamp_version AS stv2
      ON stv1.id_sale_listing = stv2.id_sale_listing
      AND stv1.rn_start = stv2.rn_end
  WHERE
    stv1.rn_start = 1
    AND stv1.id_sale_listing IS NOT NULL
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
        IF(ROW_NUMBER() OVER (PARTITION BY hpp_aud.id_house, DATE(r.ts_revision), hpp_aud.business_context ORDER BY ts_revision DESC) = 1, TRUE, FALSE) AS is_last_prediction_of_day,
        r.ts_revision AS ts_calculator_result_started,
        LEAD(r.ts_revision) OVER (PARTITION BY id_house, business_context ORDER BY r.ts_revision) AS ts_calculator_result_ended
    FROM
        datalake_ebdb_clean.house_predicted_price_aud AS hpp_aud
    INNER JOIN
        datalake_ebdb_user.user_revision_entity AS r
            ON hpp_aud.rev = r.id
)
SELECT DISTINCT
    cc.id_house,
    rsvo.id_house_listing,
    cc.id_revision,
    cc.business_context,
    cc.p_10 AS calculator_min_price,
    cc.p_30 AS calculator_p30_price,
    cc.p_50 AS calculator_price,
    cc.p_70 AS calculator_p70_price,
    cc.p_90 AS calculator_max_price,
    cc.certainty AS calculator_certainty,
    cc.is_last_prediction_of_day,
    cc.ts_calculator_result_started,
    cc.ts_calculator_result_ended
FROM
    calculator_changes AS cc
LEFT JOIN
    rent_status_version_order AS rsvo
        ON rsvo.id_house = cc.id_house
        AND cc.ts_calculator_result_started BETWEEN rsvo.ts_listing_version_start AND COALESCE(rsvo.ts_listing_version_end, TO_TIMESTAMP(CURRENT_DATE))
WHERE
  cc.business_context = 'RENT'

UNION ALL

SELECT DISTINCT
    cc.id_house,
    ssvo.id_house_listing,
    cc.id_revision,
    cc.business_context,
    cc.p_10 AS calculator_min_price,
    cc.p_30 AS calculator_p30_price,
    cc.p_50 AS calculator_price,
    cc.p_70 AS calculator_p70_price,
    cc.p_90 AS calculator_max_price,
    cc.certainty AS calculator_certainty,
    cc.is_last_prediction_of_day,
    cc.ts_calculator_result_started,
    cc.ts_calculator_result_ended
FROM
    calculator_changes AS cc
LEFT JOIN
    sale_status_version_order AS ssvo
        ON ssvo.id_house = cc.id_house
        AND cc.ts_calculator_result_started BETWEEN ssvo.ts_listing_version_start AND COALESCE(ssvo.ts_listing_version_end, TO_TIMESTAMP(CURRENT_DATE))
WHERE
  cc.business_context = 'SALE'
