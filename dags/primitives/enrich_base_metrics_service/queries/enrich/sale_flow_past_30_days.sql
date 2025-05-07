-----------------
-- Sale Flow

SELECT
    id_buyer AS id_user,
    id_house,
    MIN(ts_first_booking_created) AS ts_visit_booked,
    MIN(ts_first_visit_completed) AS ts_visit_completed,
    MIN(ts_first_offer_submitted) AS ts_offer,
    MIN(dt_sale_agreement_signed) AS ts_contract_signed,
    MIN(dt_first_offer_accepted) as ts_offer_approved,
    GREATEST(
        MIN(ts_first_booking_created),
        MIN(ts_first_visit_completed),
        MIN(ts_first_offer_submitted),
        MIN(dt_sale_agreement_signed),
        MIN(dt_first_offer_accepted)
    ) AS ts_sale_flow_latest_event
FROM datalake_sale_flows.sale_flow
WHERE
    id_buyer IS NOT NULL
    AND id_house IS NOT NULL
    -- This clause is more correct than filtering by ts_first_event
    AND
        (
         ts_first_booking_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
         OR
         ts_first_visit_completed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
         OR
         ts_first_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
         OR
         dt_sale_agreement_signed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
         OR
         dt_first_offer_accepted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
         )
GROUP BY
    id_buyer,
    id_house
