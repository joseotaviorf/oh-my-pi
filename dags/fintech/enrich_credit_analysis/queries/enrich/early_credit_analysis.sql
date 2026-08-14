WITH evaluation AS (
    SELECT
        id_credit_evaluation,
        id_user,
        id_house,
        ts_created,
        RANK() OVER (PARTITION BY id_user, id_house ORDER BY ts_created DESC) AS rank
    FROM datalake_sorting_hat_clean.early_credit_analysis
),
rent_flow AS (
  SELECT
    rf.id_rent_flow,
    rf.id_visit,
    rf.id_booking,
    rf.id_offer,
    rf.id_client,
    rf.id_house,
    rf.dt_visit,
    rf.dt_booking_created,
    offer.ts_created AS ts_offer_created
  FROM datalake_ebdb_rent_flow.rent_flow AS rf
  LEFT JOIN datalake_ebdb_clean.offer AS offer
      ON offer.id = rf.id_offer
),
eca_base AS (
  SELECT
    eca.id_house,
    eca.id_user,
    eca.id_credit_evaluation,
    eca.result,
    eca.ts_expired,
    eca.ts_created,
    eval.rank
  FROM datalake_sorting_hat_clean.early_credit_analysis AS eca
  JOIN evaluation AS eval
      ON eval.id_credit_evaluation = eca.id_credit_evaluation
),
matched_rent_flow AS (
  SELECT
    e.id_credit_evaluation,
    rf.id_visit,
    rf.id_offer,
    rf.id_booking,
    rf.id_rent_flow,
    rf.dt_visit,
    rf.dt_booking_created,
    rf.ts_offer_created
  FROM eca_base AS e
  INNER JOIN rent_flow AS rf
      ON e.id_user = rf.id_client
      AND e.id_house = rf.id_house
      AND e.ts_created BETWEEN rf.ts_offer_created - INTERVAL '1' MONTH AND rf.ts_offer_created
  UNION
  SELECT
    e.id_credit_evaluation,
    rf.id_visit,
    rf.id_offer,
    rf.id_booking,
    rf.id_rent_flow,
    rf.dt_visit,
    rf.dt_booking_created,
    rf.ts_offer_created
  FROM eca_base AS e
  INNER JOIN rent_flow AS rf
      ON e.id_user = rf.id_client
      AND e.id_house = rf.id_house
      AND e.ts_created BETWEEN rf.dt_booking_created - INTERVAL '1' MONTH AND rf.dt_booking_created
)
SELECT
    e.id_house,
    rf.id_visit,
    rf.id_offer,
    e.id_user,
    rf.id_rent_flow,
    e.id_credit_evaluation,
    e.result,
    IF(rf.id_offer IS NOT NULL, DATEDIFF(rf.ts_offer_created, e.ts_created), NULL) AS days_offer_after_early_credit_evaluation,
    IF(rf.id_booking IS NOT NULL, DATEDIFF(rf.dt_booking_created, e.ts_created), NULL) AS days_booking_after_early_credit_evaluation,
    IF(rf.id_visit IS NOT NULL, DATEDIFF(rf.dt_visit, e.ts_created), NULL) AS days_visit_after_early_credit_evaluation,
    IF(e.rank = 1, TRUE, FALSE) AS is_most_recent_evaluation,
    rf.dt_visit,
    rf.dt_booking_created AS ts_booking_created,
    rf.ts_offer_created,
    e.ts_expired AS ts_early_credit_analysis_expired,
    e.ts_created AS ts_early_credit_analysis_created
FROM eca_base AS e
LEFT JOIN matched_rent_flow AS rf
    ON rf.id_credit_evaluation = e.id_credit_evaluation
