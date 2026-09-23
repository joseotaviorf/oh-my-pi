WITH counts AS (
  SELECT
    id_rent_flow,
    id_house,
    id_tenant_prospect,
    id_owner,
    COUNT(DISTINCT id_booking) FILTER (WHERE ts_booking_created IS NOT NULL) AS nbr_bookings_created,
    COUNT(DISTINCT id_booking) FILTER (WHERE ts_visit_completed IS NOT NULL) AS nbr_visits_completed,
    COUNT(DISTINCT id_booking) FILTER (WHERE ts_visit_performed IS NOT NULL) AS nbr_visits_performed,
    COUNT(DISTINCT id_booking) FILTER (WHERE ts_booking_canceled IS NOT NULL) AS nbr_visits_canceled,
    COUNT(DISTINCT id_offer) FILTER (WHERE ts_direct_offer_submitted IS NOT NULL) AS nbr_direct_offers_submitted,
    COUNT(DISTINCT id_offer) FILTER (WHERE ts_offer_submitted IS NOT NULL) AS nbr_offers_submitted,
    COUNT(DISTINCT id_offer) FILTER (WHERE ts_offer_approved IS NOT NULL) AS nbr_offers_approved,
    COUNT(DISTINCT id_reservation) FILTER (WHERE ts_reservation_created IS NOT NULL) AS nbr_reservations_created,
    COUNT(DISTINCT id_proposal) FILTER (WHERE ts_proposal_created IS NOT NULL) AS nbr_proposals_created,
    COUNT(DISTINCT id_proposal) FILTER (WHERE ts_guarantee_paid IS NOT NULL) AS nbr_guarantees_paid,
    COUNT(DISTINCT id_contract) FILTER (WHERE ts_contract_created IS NOT NULL) AS nbr_contracts_created,
    COUNT(DISTINCT id_contract) FILTER (WHERE ts_contract_signed IS NOT NULL) AS nbr_contracts_signed,
    COUNT(DISTINCT id_contract) FILTER (WHERE dt_contract_terminated IS NOT NULL) AS nbr_contracts_terminated,
    COUNT(DISTINCT id_advance_payment) FILTER (WHERE ts_advance_payment_created IS NOT NULL) AS nbr_advance_payments_created,
    COUNT(DISTINCT id_advance_payment) FILTER (WHERE ts_advance_payment_paid IS NOT NULL) AS nbr_advance_payments_paid,
    SUM(tta_messages) AS nbr_tta_messages
  FROM
    datalake_rent_flows.rent_flows
  GROUP BY 1, 2, 3, 4
),
min_max_events AS (
  SELECT
    id_rent_flow,
    id_house,
    id_tenant_prospect,
    id_owner,
    MIN(id_booking) AS id_first_booking,
    MIN(id_reservation) AS id_first_reservation,
    MIN(id_offer) AS id_first_offer,
    MIN(id_proposal) AS id_first_proposal,
    MIN(id_contract) AS id_first_contract,
    MAX(id_booking) AS id_last_booking,
    MAX(id_reservation) AS id_last_reservation,
    MAX(id_offer) AS id_last_offer,
    MAX(id_proposal) AS id_last_proposal,
    MAX(id_contract) AS id_last_contract,
    MIN(id_advance_payment) AS id_first_advance_payment,
    MAX(id_advance_payment) AS id_last_advance_payment,
    MIN(ts_rent_flow_event) AS ts_first_event,
    MIN(ts_booking_created) AS ts_first_booking_created,
    MIN(ts_visit_completed) AS ts_first_visit_completed,
    MIN(ts_visit_performed) AS ts_first_visit_performed,
    MIN(ts_direct_offer_submitted) AS ts_first_direct_offer_submitted,
    MIN(ts_offer_submitted) AS ts_first_offer_submitted,
    MIN(ts_offer_approved) AS ts_first_offer_approved,
    MIN(ts_contract_created) AS ts_first_contract_created,
    MIN(ts_contract_signed) AS ts_first_contract_signed,
    MIN(ts_advance_payment_created) AS ts_first_advance_payment_created,
    MIN(ts_advance_payment_paid) AS ts_first_advance_payment_paid,
    MAX(ts_rent_flow_event) AS ts_last_event,
    MAX(ts_booking_created) AS ts_last_booking_created,
    MAX(ts_visit_completed) AS ts_last_visit_completed,
    MAX(ts_visit_performed) AS ts_last_visit_performed,
    MAX(ts_offer_submitted) AS ts_last_offer_submitted,
    MAX(ts_offer_approved) AS ts_last_offer_approved,
    MAX(ts_contract_created) AS ts_last_contract_created,
    MAX(ts_contract_signed) AS ts_last_contract_signed,
    MAX(ts_advance_payment_created) AS ts_last_advance_payment_created,
    MAX(ts_advance_payment_paid) AS ts_last_advance_payment_paid
  FROM
    datalake_rent_flows.rent_flows
  GROUP BY 1, 2, 3, 4
),
last_rent_flow_event AS (
    /** As this model is dedicated to the very last update of the rent flow, we decided to always get
        the most recent update of it (since the enriched base table has multiple lines for each rent flow),
        so we dedupe with ROW_NUMBER() on the rent flow and its last event. **/
    SELECT
        id_rent_flow,
        id_house,
        id_tenant_prospect,
        id_owner,
        id_region,
        uuid_company,
        partner_3p_supply,
        country_code,
        first_touchpoint,
        status,
        is_step_rejected,
        is_valid_rent_flow,
        has_visit_flow,
        has_offer_flow,
        has_direct_offer_flow,
        has_tta_flow,
        ts_created,
        ts_updated
    FROM (
        SELECT
            id_rent_flow,
            id_house,
            id_tenant_prospect,
            id_owner,
            id_region,
            uuid_company,
            partner_3p_supply,
            country_code,
            first_touchpoint,
            status,
            is_step_rejected,
            is_valid_rent_flow,
            has_visit_flow,
            has_offer_flow,
            has_direct_offer_flow,
            has_tta_flow,
            ts_created,
            ts_updated,
            ts_rent_flow_event,
            ROW_NUMBER() OVER (PARTITION BY id_rent_flow ORDER BY ts_rent_flow_event DESC) AS _w
        FROM
            datalake_rent_flows.rent_flows
    ) AS _t
    WHERE
        _w = 1
)
SELECT
  rf.id_rent_flow AS sk_rent_flow,
  COALESCE(rt.id_rent_flow_type, -1) AS sk_rent_flow_type,
  COALESCE(rf.id_house, -1) AS sk_house,
  COALESCE(rf.id_tenant_prospect, -1) AS sk_tenant_prospect,
  COALESCE(rf.id_owner, -1) AS sk_owner,
  COALESCE(m.id_first_booking, -1) AS sk_first_booking,
  COALESCE(m.id_last_booking, -1) AS sk_last_booking,
  COALESCE(m.id_first_reservation, -1) AS sk_first_reservation,
  COALESCE(m.id_last_reservation, -1) AS sk_last_reservation,
  COALESCE(m.id_first_offer, -1) AS sk_first_offer,
  COALESCE(m.id_last_offer, -1) AS sk_last_offer,
  COALESCE(m.id_first_proposal, -1) AS sk_first_proposal,
  COALESCE(m.id_last_proposal, -1) AS sk_last_proposal,
  COALESCE(m.id_first_contract, -1) AS sk_first_contract,
  COALESCE(m.id_last_contract, -1) AS sk_last_contract,
  COALESCE(m.id_first_advance_payment, -1) AS sk_first_advance_payment,
  COALESCE(m.id_last_advance_payment, -1) AS sk_last_advance_payment,
  COALESCE(rf.id_region, -1) AS sk_region,
  COALESCE(IF(rf.uuid_company IS NOT NULL, cb.sk_broker, NULL), '-1') AS sk_broker_supply,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_event, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_event_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_booking_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_booking_created_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_visit_completed, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_visit_completed_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_visit_performed, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_visit_performed_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_offer_submitted, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_offer_submitted_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_offer_approved, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_offer_approved_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_contract_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_contract_created_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_contract_signed, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_contract_signed_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_advance_payment_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_advance_payment_created_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_first_advance_payment_paid, 'yyyyMMdd') AS BIGINT), -1) AS sk_first_advance_payment_paid_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_event, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_event_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_booking_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_booking_created_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_visit_completed, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_visit_completed_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_visit_performed, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_visit_performed_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_offer_submitted, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_offer_submitted_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_offer_approved, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_offer_approved_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_contract_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_contract_created_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_contract_signed, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_contract_signed_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_advance_payment_created, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_advance_payment_created_date,
  COALESCE(CAST(DATE_FORMAT(m.ts_last_advance_payment_paid, 'yyyyMMdd') AS BIGINT), -1) AS sk_last_advance_payment_paid_date,
  rf.country_code,
  DATEDIFF(ts_last_event, ts_first_event) AS days_first_touchpoint_to_last,
  DATEDIFF(NOW(), ts_last_event) AS days_since_last_event,
  nbr_bookings_created,
  nbr_visits_completed,
  nbr_visits_performed,
  nbr_visits_canceled,
  nbr_reservations_created,
  nbr_direct_offers_submitted,
  nbr_offers_submitted,
  nbr_offers_approved,
  nbr_proposals_created,
  nbr_guarantees_paid,
  nbr_contracts_created,
  nbr_contracts_signed,
  nbr_contracts_terminated,
  nbr_advance_payments_created,
  nbr_advance_payments_paid,
  nbr_tta_messages,
  rf.ts_created,
  rf.ts_updated,
  ts_first_event,
  ts_first_booking_created,
  ts_first_visit_completed,
  ts_first_visit_performed,
  ts_first_direct_offer_submitted,
  ts_first_offer_submitted,
  ts_first_offer_approved,
  ts_first_contract_created,
  ts_first_contract_signed,
  ts_first_advance_payment_created,
  ts_first_advance_payment_paid,
  ts_last_event,
  ts_last_booking_created,
  ts_last_visit_completed,
  ts_last_visit_performed,
  ts_last_offer_submitted,
  ts_last_offer_approved,
  ts_last_contract_created,
  ts_last_contract_signed,
  ts_last_advance_payment_created,
  ts_last_advance_payment_paid,
  NOW() AS ts_load
FROM
    last_rent_flow_event AS rf
JOIN
  counts AS c
    ON rf.id_rent_flow = c.id_rent_flow
    AND rf.id_house = c.id_house
    AND rf.id_tenant_prospect = c.id_tenant_prospect
JOIN
  min_max_events AS m
    ON rf.id_rent_flow = m.id_rent_flow
    AND rf.id_house = m.id_house
    AND rf.id_tenant_prospect = m.id_tenant_prospect
JOIN
    datalake_rent_flows.rent_flows_types AS rt
        ON COALESCE(rf.country_code, -1) = COALESCE(rt.country_code, -1)
        AND COALESCE(rf.first_touchpoint, -1) = COALESCE(rt.first_touchpoint, -1)
        AND COALESCE(rf.status, -1) = COALESCE(rt.status, -1)
        AND COALESCE(CAST(rf.is_step_rejected AS INT), -1) = COALESCE(CAST(rt.is_step_rejected AS INT), -1)
        AND COALESCE(CAST(rf.is_valid_rent_flow AS INT), -1) = COALESCE(CAST(rt.is_valid_rent_flow AS INT), -1)
        AND COALESCE(CAST(rf.has_visit_flow AS INT), -1) = COALESCE(CAST(rt.has_visit_flow AS INT), -1)
        AND COALESCE(CAST(rf.has_offer_flow AS INT), -1) = COALESCE(CAST(rt.has_offer_flow AS INT), -1)
        AND COALESCE(CAST(rf.has_direct_offer_flow AS INT), -1) = COALESCE(CAST(rt.has_direct_offer_flow AS INT), -1)
        AND COALESCE(CAST(rf.has_tta_flow AS INT), -1) = COALESCE(CAST(rt.has_tta_flow AS INT), -1)
        AND IF(c.nbr_contracts_signed > 0, TRUE, FALSE) = COALESCE(rt.had_contract_signed, FALSE)
LEFT JOIN
    core_brokers.brokers AS cb
        ON rf.uuid_company = cb.uuid_company