-----------------
-- Rent Flow

SELECT
    id_tenant_prospect as id_user,
    id_house,
    MIN(ts_booking_created) AS ts_visit_booked,
    MIN(ts_visit_completed) AS ts_visit_completed,
    MIN(coalesce(ts_direct_offer_submitted, ts_offer_submitted)) AS ts_offer,
    MIN(ts_contract_signed) AS ts_contract_signed,
    MIN(ts_direct_offer_submitted) AS ts_direct_offer,
    MIN(ts_offer_submitted) AS ts_offer_submitted,
    MIN(ts_offer_approved) AS ts_offer_approved,
    GREATEST(
        MIN(ts_booking_created),
        MIN(ts_visit_completed),
        MIN(ts_direct_offer_submitted),
        MIN(ts_offer_submitted),
        MIN(ts_contract_signed),
        MIN(ts_offer_approved)
    ) AS ts_rent_flow_latest_event
FROM
    datalake_rent_flows.rent_flows
WHERE
    id_tenant_prospect IS NOT NULL
    AND id_house IS NOT NULL
    -- This clause is more correct than filtering by ts_rent_flow_event
    AND
            (
             ts_booking_created BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
             OR
             ts_visit_completed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
             OR
             ts_direct_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
             OR
             ts_offer_submitted BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
             OR
             ts_contract_signed BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
             OR
             ts_offer_approved BETWEEN DATE_SUB(DATE('{start_date}'), {days_past_30}) AND DATE('{end_date}')
            )
GROUP BY
    id_tenant_prospect,
    id_house
