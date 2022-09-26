WITH evaluation AS (
    SELECT
        id_credit_evaluation,
        id_user,
        id_house,
        ts_created,
        RANK() OVER (PARTITION BY id_user, id_house ORDER BY ts_created DESC) AS rank
    FROM datalake_sorting_hat_clean.early_credit_analysis
)

SELECT
    eca.id_house, 
    rf.id_visit, 
    rf.id_offer, 
    eca.id_user,
    rf.id_rent_flow, 
    eca.id_credit_evaluation,
    eca.result,
    IF(rf.id_offer IS NOT NULL, DATEDIFF(offer.ts_created, eca.ts_created), NULL) AS days_offer_after_early_credit_evaluation,
    IF(rf.id_visit IS NOT NULL, DATEDIFF(rf.dt_visit, eca.ts_created), NULL) AS days_visit_after_early_credit_evaluation,
    IF(eval.rank = 1, TRUE, FALSE) AS is_most_recent_evaluation,
    rf.dt_visit,
    offer.ts_created AS ts_offer_created,
    eca.ts_created AS ts_early_credit_analysis_created
FROM datalake_sorting_hat_clean.early_credit_analysis AS eca
JOIN evaluation AS eval
    ON eval.id_credit_evaluation = eca.id_credit_evaluation
LEFT JOIN datalake_ebdb_rent_flow.rent_flow AS rf
    ON eca.id_user = rf.id_client
    AND eca.id_house = rf.id_house
LEFT JOIN 
    datalake_ebdb_clean.offer AS offer
    ON offer.id = rf.id_offer