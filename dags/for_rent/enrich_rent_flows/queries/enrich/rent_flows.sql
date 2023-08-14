WITH rent_flow_base AS (
  SELECT
    rde.id_rent_flow,
    rde.id_house,
    rde.id_tenant_prospect,
    rde.id_owner,
    rde.id_booking,
    r.id_reservation,
    rde.id_offer,
    rde.id_proposal,
    rde.id_contract,
    rde.id_region,
    rde.id_event_type,
    rde.country_code,
    rf.status,
    b.status AS booking_status,
    r.status AS reservation_status,
    of.status AS offer_status,
    p.status AS proposal_status,
    c.status AS contract_status,
    rf.is_step_rejected,
    rf.ts_created,
    rf.ts_updated,
    IF(id_event_type = 1, ts_event, NULL) AS ts_booking_created,
    b.ts_first_canceled AS ts_booking_canceled,
    IF(id_event_type = 2, ts_event, NULL) AS ts_visit_completed,
    IF(id_event_type = 2 AND b.is_visit_performed = TRUE, ts_event, NULL) AS ts_visit_performed,
    r.ts_created AS ts_reservation_created,
    IF(id_event_type = 3, ts_event, NULL) AS ts_offer_submitted,
    IF(id_event_type = 4, ts_event, NULL) AS ts_offer_approved,
    p.ts_created AS ts_proposal_created,
    p.ts_approved AS ts_proposal_approved,
    p.ts_guarantee AS ts_guarantee_processed,
    p.ts_guarantee_paid,
    IF(c.ts_created IS NOT NULL, c.ts_created, NULL) AS ts_contract_created,
    IF(id_event_type = 9, ts_event, NULL) AS ts_contract_signed,
    IF(c.status = 'Finalizado', dt_termination, NULL) AS ts_contract_terminated,
    rde.ts_event AS ts_rent_flow_event
  FROM
    datalake_rent_demand_events.rent_demand_events AS rde
  LEFT JOIN
    datalake_ebdb_clean.rent_flow AS rf
      ON rde.id_rent_flow = rf.id
  LEFT JOIN
    datalake_booking.booking AS b
      ON rde.id_booking = b.id
  LEFT JOIN
    datalake_offer.offer AS of
      ON rde.id_offer = of.id_offer_context
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON rde.id_contract = c.id
  LEFT JOIN
    datalake_kill_queue.reservation AS r
      ON rde.id_rent_flow = r.id_rent_flow
  LEFT JOIN
    datalake_proposal.proposal AS p
      ON rde.id_proposal = p.id
),
flow_type AS (
  SELECT
    rf.id_rent_flow,
    rf.id_house,
    rf.id_tenant_prospect,
    rf.id_owner,
    SUM(msg_sent) AS tta_messages,
    CASE
      WHEN (MIN(rf.ts_booking_created) < MIN(rf.ts_offer_submitted)) AND (MIN(rf.ts_booking_created) < MIN(tta.first_message_ts)) THEN 'V'
      WHEN (MIN(rf.ts_offer_submitted) < MIN(rf.ts_booking_created)) AND (MIN(rf.ts_offer_submitted) < MIN(tta.first_message_ts)) THEN 'DO'
      WHEN (MIN(tta.first_message_ts) < MIN(rf.ts_booking_created)) AND (MIN(tta.first_message_ts) < MIN(rf.ts_offer_submitted)) THEN 'TTA'
      ELSE NULL
    END AS first_touchpoint,
    IF(COUNT(rf.ts_booking_created) > 0, TRUE, FALSE) AS has_visit_flow,
    IF(COUNT(rf.ts_offer_submitted) > 0, TRUE, FALSE) AS has_offer_flow,
    IF(COUNT(tta.first_message_ts) > 0, TRUE, FALSE) AS has_tta_flow
  FROM
    rent_flow_base AS rf
  LEFT JOIN
    datalake_talk_to_agent.talk_to_agent AS tta
        ON rf.id_house = tta.house_id
        AND rf.id_tenant_prospect = tta.tenant_id
  GROUP BY 1, 2, 3, 4
)
SELECT
    rf.id_rent_flow,
    rf.id_house,
    rf.id_tenant_prospect,
    rf.id_owner,
    rf.id_booking,
    rf.id_reservation,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,
    rf.id_region,
    rf.id_event_type,
    rf.country_code,
    ft.first_touchpoint,
    rf.status,
    rf.booking_status,
    rf.reservation_status,
    rf.offer_status,
    rf.proposal_status,
    rf.contract_status,
    ft.tta_messages,
    rf.is_step_rejected,
    ft.has_visit_flow,
    ft.has_offer_flow,
    ft.has_tta_flow,
    rf.ts_created,
    rf.ts_updated,
    rf.ts_booking_created,
    rf.ts_booking_canceled,
    rf.ts_visit_completed,
    rf.ts_visit_performed,
    rf.ts_reservation_created,
    rf.ts_offer_submitted,
    rf.ts_offer_approved,
    rf.ts_proposal_created,
    rf.ts_proposal_approved,
    rf.ts_guarantee_processed,
    rf.ts_guarantee_paid,
    rf.ts_contract_created,
    rf.ts_contract_signed,
    rf.ts_contract_terminated,
    rf.ts_rent_flow_event
FROM
    rent_flow_base AS rf
JOIN
    flow_type AS ft
        ON rf.id_rent_flow = ft.id_rent_flow
        AND rf.id_tenant_prospect = ft.id_tenant_prospect
        AND rf.id_house = ft.id_house
