SELECT
    hpp_aud.id_house,
    hpp_aud.rev AS id_revision,
    hpp_aud.business_context,
    hpp_aud.p_10 AS calculator_min_price,
    hpp_aud.p_20 AS calculator_p20_price,
    hpp_aud.p_30 AS calculator_p30_price,
    hpp_aud.p_40 AS calculator_p40_price,
    hpp_aud.p_50 AS calculator_price,
    hpp_aud.p_60 AS calculator_p60_price,
    hpp_aud.p_70 AS calculator_p70_price,
    hpp_aud.p_80 AS calculator_p80_price,
    hpp_aud.p_90 AS calculator_max_price,
    hpp_aud.certainty AS calculator_certainty,
    (
        ROW_NUMBER() OVER (
            PARTITION BY
                hpp_aud.id_house,
                hpp_aud.business_context
            ORDER BY
                ure.ts_revision DESC
        ) = 1
    ) AS is_last_prediction,
    (
        ROW_NUMBER() OVER (
            PARTITION BY
                hpp_aud.id_house,
                DATE(ure.ts_revision),
                hpp_aud.business_context
            ORDER BY
                ure.ts_revision DESC
        ) = 1
    ) AS is_last_prediction_of_day,
    ure.ts_revision AS ts_calculator_result_started,
    LEAD(ure.ts_revision) OVER (PARTITION BY id_house, business_context ORDER BY ure.ts_revision) AS ts_calculator_result_ended
FROM
    datalake_ebdb_clean.house_predicted_price_aud AS hpp_aud
INNER JOIN
    datalake_ebdb_user.user_revision_entity AS ure
        ON hpp_aud.rev = ure.id
WHERE
    ure.ts_revision >= TIMESTAMP('2022-04-01') -- removing very old predictions, where the certainty field was not filled in
    AND ure.ts_revision < TIMESTAMP(CURRENT_DATE)
