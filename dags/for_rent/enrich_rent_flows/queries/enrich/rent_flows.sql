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
    rde.uuid_company,
    rde.id_company_hubspot,
    rde.partner_3p_supply,
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
    b.ts_created AS ts_booking_created,
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
    c.ts_created AS ts_contract_created,
    IF(id_event_type = 9, ts_event, NULL) AS ts_contract_signed,
    c.dt_termination AS dt_contract_terminated,
    rde.ts_event AS ts_rent_flow_event
  FROM
    datalake_rent_demand_events.rent_demand_events AS rde
  JOIN
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
rent_flow_type AS (
  SELECT
    rf.id_rent_flow,
    rf.id_house,
    rf.id_tenant_prospect,
    rf.id_owner,
    SUM(msg_sent) AS tta_messages,
    CASE
      WHEN MIN(rf.ts_booking_created) < LEAST(MIN(rf.ts_offer_submitted), MIN(CAST(tta.first_message_ts AS TIMESTAMP)), NOW()) THEN 'VISIT'
      WHEN MIN(rf.ts_offer_submitted) < LEAST(MIN(rf.ts_booking_created), MIN(CAST(tta.first_message_ts AS TIMESTAMP)), NOW()) THEN 'DIRECT'
      WHEN MIN(CAST(tta.first_message_ts AS TIMESTAMP)) < LEAST(MIN(rf.ts_booking_created), MIN(rf.ts_offer_submitted), NOW()) THEN 'TTA'
      ELSE 'UNKNOWN'
    END AS first_touchpoint,
    IF(COUNT(rf.ts_booking_created) > 0, TRUE, FALSE) AS has_visit_flow,
    IF(COUNT(rf.ts_offer_submitted) > 0, TRUE, FALSE) AS has_offer_flow,
    IF(COUNT(rf.ts_offer_submitted) > 0 AND MIN(rf.ts_offer_submitted) < COALESCE(MIN(rf.ts_booking_created), CURRENT_DATE), TRUE, FALSE) AS has_direct_offer_flow,
    IF(COUNT(tta.first_message_ts) > 0, TRUE, FALSE) AS has_tta_flow,
    MIN(rf.ts_booking_created) AS ts_first_booking_created,
    MIN(rf.ts_offer_submitted) AS ts_first_offer_submitted
  FROM
    rent_flow_base AS rf
  LEFT JOIN
    datalake_talk_to_agent.talk_to_agent AS tta
        ON rf.id_house = tta.house_id
        AND rf.id_tenant_prospect = tta.tenant_id
  GROUP BY 1, 2, 3, 4
),
valid_rent_flows AS (
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
      rf.uuid_company,
      rf.id_company_hubspot,
      rf.partner_3p_supply,
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
      TRUE AS is_valid_rent_flow,
      ft.has_visit_flow,
      ft.has_offer_flow,
      ft.has_direct_offer_flow,
      ft.has_tta_flow,
      rf.ts_created,
      rf.ts_updated,
      rf.ts_booking_created,
      rf.ts_booking_canceled,
      rf.ts_visit_completed,
      rf.ts_visit_performed,
      rf.ts_reservation_created,
      CASE
        WHEN of.ts_first_sent IS NOT NULL AND of.ts_first_sent < COALESCE(ft.ts_first_booking_created, CURRENT_DATE) THEN of.ts_first_sent
        WHEN of.ts_first_sent IS NULL AND ft.ts_first_offer_submitted < COALESCE(ft.ts_first_booking_created, CURRENT_DATE) THEN ft.ts_first_offer_submitted
        ELSE NULL
      END AS ts_direct_offer_submitted,
      rf.ts_offer_submitted,
      rf.ts_offer_approved,
      rf.ts_proposal_created,
      rf.ts_proposal_approved,
      rf.ts_guarantee_processed,
      rf.ts_guarantee_paid,
      rf.ts_contract_created,
      rf.ts_contract_signed,
      rf.dt_contract_terminated,
      rf.ts_rent_flow_event
  FROM
      rent_flow_base AS rf
  JOIN
      rent_flow_type AS ft
          ON rf.id_rent_flow = ft.id_rent_flow
          AND rf.id_tenant_prospect = ft.id_tenant_prospect
          AND rf.id_house = ft.id_house
  LEFT JOIN
    datalake_offer.offer AS of
        ON rf.id_offer = of.id_offer_context
  LEFT JOIN
    datalake_booking.booking AS b
      ON rf.id_booking = b.id
),
invalid_rent_flows AS (
  /** Rent flows that are not following all our rules applied on Rent Demand Event to consider an demand event (VB, OS, CS, etc.) valid.
    E.g. if a rent flow had just a Direct Offer and it hasn't timestamp of when it was first sent and it ended in this step, this rent flow
    is not counted on Rent Demand Events, but will be here.
  **/
  WITH base AS (
    SELECT
      rf.id AS id_rent_flow,
      rf.id_house,
      rf.id_client AS id_tenant_prospect,
      h.id_user AS id_owner,
      b.id AS id_booking,
      r.id_reservation,
      of.id_offer_context AS id_offer,
      pp.id AS id_proposal,
      c.id AS id_contract,
      h.id_region,
      NULL AS id_event_type,
      IF(h.is_rent_3p_supply, h.uuid_company, NULL) AS uuid_company,
      IF(h.is_rent_3p_supply, h.id_company_hubspot, NULL) AS id_company_hubspot,
      IF(h.is_rent_3p_supply, h.partner_3p_supply, NULL) AS partner_3p_supply,
      h.country_code,
      rf.status,
      b.status AS booking_status,
      r.status AS reservation_status,
      of.status AS offer_status,
      pp.status AS proposal_status,
      c.status AS contract_status,
      rf.is_step_rejected,
      FALSE AS is_valid_rent_flow,
      rf.ts_created,
      rf.ts_updated,
      b.ts_created AS ts_booking_created,
      b.ts_first_canceled AS ts_booking_canceled,
      IF(b.is_visit_completed = TRUE, dt_booking, NULL) AS ts_visit_completed,
      IF(b.is_visit_performed = TRUE, dt_booking, NULL) AS ts_visit_performed,
      r.ts_created AS ts_reservation_created,
      of.ts_first_sent AS ts_offer_submitted,
      IF(of.status IN ('Aprovada', 'ACCEPTED'), of.ts_analyzed, NULL) AS ts_offer_approved,
      pp.ts_created AS ts_proposal_created,
      pp.ts_approved AS ts_proposal_approved,
      pp.ts_guarantee AS ts_guarantee_processed,
      pp.ts_guarantee_paid,
      c.ts_created AS ts_contract_created,
      c.ts_signed AS ts_contract_signed,
      c.dt_termination AS dt_contract_terminated,
      NULL AS ts_rent_flow_event
    FROM
      datalake_ebdb_clean.rent_flow AS rf
    JOIN
      datalake_ebdb_listing.house AS h
        ON rf.id_house = h.id
    JOIN
      datalake_ebdb_clean.house AS hh
        ON hh.id = h.id
    LEFT JOIN
      datalake_booking.booking AS b
        ON b.id_rent_flow = rf.id
    LEFT JOIN
      datalake_offer.offer AS of
        ON of.id_rent_flow = rf.id
    LEFT JOIN
      datalake_proposal.proposal AS pp
        ON pp.id_offer = of.id
    LEFT JOIN
      datalake_ebdb_contract.contract AS c
        ON c.id_proposal = pp.id
    LEFT JOIN
      datalake_kill_queue.reservation AS r
        ON rf.id = r.id_rent_flow
    ),
    flow_type AS (
      SELECT
        rf.id_rent_flow,
        rf.id_house,
        rf.id_tenant_prospect,
        rf.id_owner,
        SUM(msg_sent) AS tta_messages,
        CASE
          WHEN MIN(rf.ts_booking_created) < LEAST(MIN(rf.ts_offer_submitted), MIN(CAST(tta.first_message_ts AS TIMESTAMP)), NOW()) THEN 'VISIT'
          WHEN MIN(rf.ts_offer_submitted) < LEAST(MIN(rf.ts_booking_created), MIN(CAST(tta.first_message_ts AS TIMESTAMP)), NOW()) THEN 'DIRECT'
          WHEN MIN(CAST(tta.first_message_ts AS TIMESTAMP)) < LEAST(MIN(rf.ts_booking_created), MIN(rf.ts_offer_submitted), NOW()) THEN 'TTA'
          ELSE 'UNKNOWN'
        END AS first_touchpoint,
        IF(COUNT(rf.ts_booking_created) > 0, TRUE, FALSE) AS has_visit_flow,
        IF(COUNT(rf.ts_offer_submitted) > 0, TRUE, FALSE) AS has_offer_flow,
        IF(COUNT(rf.ts_offer_submitted) > 0 AND MIN(rf.ts_offer_submitted) < COALESCE(MIN(rf.ts_booking_created), CURRENT_DATE), TRUE, FALSE) AS has_direct_offer_flow,
        IF(COUNT(tta.first_message_ts) > 0, TRUE, FALSE) AS has_tta_flow,
        MIN(rf.ts_booking_created) AS ts_first_booking_created,
        MIN(rf.ts_offer_submitted) AS ts_first_offer_submitted
      FROM
        base AS rf
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
      rf.uuid_company,
      rf.id_company_hubspot,
      rf.partner_3p_supply,
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
      FALSE AS is_valid_rent_flow,
      ft.has_visit_flow,
      ft.has_offer_flow,
      ft.has_direct_offer_flow,
      ft.has_tta_flow,
      rf.ts_created,
      rf.ts_updated,
      rf.ts_booking_created,
      rf.ts_booking_canceled,
      rf.ts_visit_completed,
      rf.ts_visit_performed,
      rf.ts_reservation_created,
      CASE
        WHEN of.ts_first_sent IS NOT NULL AND of.ts_first_sent < COALESCE(ft.ts_first_booking_created, CURRENT_DATE) THEN of.ts_first_sent
        WHEN of.ts_first_sent IS NULL AND ft.ts_first_offer_submitted < COALESCE(ft.ts_first_booking_created, CURRENT_DATE) THEN ft.ts_first_offer_submitted
        ELSE NULL
      END AS ts_direct_offer_submitted,
      rf.ts_offer_submitted,
      rf.ts_offer_approved,
      rf.ts_proposal_created,
      rf.ts_proposal_approved,
      rf.ts_guarantee_processed,
      rf.ts_guarantee_paid,
      rf.ts_contract_created,
      rf.ts_contract_signed,
      rf.dt_contract_terminated,
      rf.ts_rent_flow_event
    FROM
        base AS rf
    JOIN
        flow_type AS ft
            ON rf.id_rent_flow = ft.id_rent_flow
            AND rf.id_tenant_prospect = ft.id_tenant_prospect
            AND rf.id_house = ft.id_house
    LEFT JOIN
      datalake_offer.offer AS of
          ON rf.id_offer = of.id_offer_context
    LEFT JOIN
      datalake_booking.booking AS b
        ON rf.id_booking = b.id
)
SELECT *
FROM
  valid_rent_flows
UNION ALL
SELECT *
FROM
  invalid_rent_flows
WHERE
  id_rent_flow
    NOT IN (SELECT id_rent_flow FROM valid_rent_flows)
