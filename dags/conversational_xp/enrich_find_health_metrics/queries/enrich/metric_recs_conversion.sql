WITH rent_sale_flow AS (
  SELECT
    id_tenant_prospect AS id_user,
    id_house,
    'RENT' AS business_context,
    MIN(ts_booking_created) AS ts_visit_booked,
    MIN(ts_direct_offer_submitted) AS ts_direct_offer,
    MIN(COALESCE(ts_direct_offer_submitted, ts_offer_submitted)) AS ts_offer,
    MIN(ts_contract_signed) AS ts_contract_signed,
    LEAST(
      COALESCE(MIN(ts_booking_created), MIN(ts_direct_offer_submitted)),
      COALESCE(MIN(ts_direct_offer_submitted), MIN(ts_booking_created))
    ) AS ts_first_flow_action
  FROM datalake_rent_flows.rent_flows
  WHERE
    NOT id_tenant_prospect IS NULL
    AND NOT id_house IS NULL
    AND (
      ts_booking_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
      OR ts_direct_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    )
  GROUP BY
    1,
    2,
    3
  UNION ALL
  SELECT
    id_buyer AS id_user,
    id_house,
    'SALE' AS business_context,
    MIN(ts_first_booking_created) AS ts_visit_booked,
    NULL AS ts_direct_offer,
    MIN(ts_first_offer_submitted) AS ts_offer,
    MIN(dt_sale_agreement_signed) AS ts_contract_signed,
    MIN(ts_first_booking_created) AS ts_first_flow_action
  FROM datalake_sale_flows.sale_flow
  WHERE
    NOT id_buyer IS NULL
    AND NOT id_house IS NULL
    AND (
      ts_first_booking_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
      OR ts_first_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    )
  GROUP BY
    1,
    2,
    3
), 
recs_impressions_actions AS (
  SELECT
    GET_JSON_OBJECT(ids, '$.id_user') AS id_user,
    GET_JSON_OBJECT(ids, '$.id_house') AS id_house,
    GET_JSON_OBJECT(dimensions, '$.business_context') AS business_context,
    GET_JSON_OBJECT(metrics, '$.click') = '1' AS is_rec_click,
    GET_JSON_OBJECT(metrics, '$.direct_offer') = '1' AS has_direct_offer,
    GET_JSON_OBJECT(metrics, '$.offer') = '1' AS has_offer,
    GET_JSON_OBJECT(metrics, '$.visit_booked') = '1' AS has_visit_booked,
    GET_JSON_OBJECT(metrics, '$.contract_signed') = '1' AS has_contract_signed,
    GET_JSON_OBJECT(timestamps, '$.ts_recommendation') AS ts_recommendation,
    GET_JSON_OBJECT(timestamps, '$.ts_direct_offer') AS ts_direct_offer,
    GET_JSON_OBJECT(timestamps, '$.ts_offer') AS ts_offer,
    GET_JSON_OBJECT(timestamps, '$.ts_visit_booked') AS ts_visit_booked,
    GET_JSON_OBJECT(timestamps, '$.ts_contract_signed') AS ts_contract_signed
  FROM datalake_search.recs_impressions_processed
  WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
    AND GET_JSON_OBJECT(metrics, '$.click') = '1'
    AND (
      GET_JSON_OBJECT(metrics, '$.direct_offer') = '1'
      OR GET_JSON_OBJECT(metrics, '$.visit_booked') = '1'
    ) /* filter users who clicked on a recommendation and did VB or DO */
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13
)
SELECT
  rent_sale_flow.id_user,
  rent_sale_flow.id_house,
  CONCAT(rent_sale_flow.id_user, rent_sale_flow.id_house) AS id_user_house,
  rent_sale_flow.business_context,
  IF(NOT rent_sale_flow.ts_direct_offer IS NULL, 'Direct Offer', 'Visit Booked') AS user_house_first_contact,
  COALESCE(recs_impressions_actions.is_rec_click, FALSE) AS is_rec_click,
  IF(
    recs_impressions_actions.has_visit_booked OR NOT rent_sale_flow.ts_visit_booked IS NULL,
    TRUE,
    FALSE
  ) AS has_visit_booked,
  IF(
    recs_impressions_actions.has_direct_offer OR NOT rent_sale_flow.ts_direct_offer IS NULL,
    TRUE,
    FALSE
  ) AS has_direct_offer,
  IF(recs_impressions_actions.has_offer OR NOT rent_sale_flow.ts_offer IS NULL, TRUE, FALSE) AS has_offer,
  IF(
    recs_impressions_actions.has_contract_signed
    OR NOT rent_sale_flow.ts_contract_signed IS NULL,
    TRUE,
    FALSE
  ) AS has_contract_signed,
  DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_visit_booked) AS days_from_rec_click_to_visit_booked,
  COALESCE(
    DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_visit_booked) <= 14,
    FALSE
  ) AS is_rec_click_and_visit_booked_within_14_days,
  DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_direct_offer) AS days_from_rec_click_to_direct_offer,
  COALESCE(
    DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_direct_offer) <= 14,
    FALSE
  ) AS is_rec_click_and_direct_offer_within_14_days,
  COALESCE(
    DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_visit_booked) <= 14
    OR DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_direct_offer) <= 14,
    FALSE
  ) AS is_rec_click_and_vb_or_do_within_14_days,
  DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_offer) AS days_from_rec_click_to_offer,
  COALESCE(
    DATEDIFF(DAY, recs_impressions_actions.ts_recommendation, recs_impressions_actions.ts_offer) <= 14,
    FALSE
  ) AS is_rec_click_and_offer_within_14_days,
  rent_sale_flow.ts_first_flow_action,
  YEAR(rent_sale_flow.ts_first_flow_action) AS year,
  MONTH(rent_sale_flow.ts_first_flow_action) AS month,
  DAY(rent_sale_flow.ts_first_flow_action) AS day
FROM rent_sale_flow
LEFT JOIN recs_impressions_actions
  ON rent_sale_flow.id_house = recs_impressions_actions.id_house
  AND rent_sale_flow.id_user = recs_impressions_actions.id_user
  AND rent_sale_flow.business_context = recs_impressions_actions.business_context
GROUP BY ALL