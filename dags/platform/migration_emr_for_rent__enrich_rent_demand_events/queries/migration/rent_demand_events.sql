WITH proposal_events AS (
  SELECT
    GET_JSON_OBJECT(payload, '$.payload.aggregateId') AS id_proposal,
    GET_JSON_OBJECT(payload, '$.payload.status') AS status,
    CAST(GET_JSON_OBJECT(payload, '$.eventDate') AS TIMESTAMP) AS event_date
  FROM
    datalake_docx_clean.message
  WHERE
    GET_JSON_OBJECT(payload, '$.eventName') = 'TENANT_DOCUMENTATION_STATUS_EVENT'
  ORDER BY
    ts_created
),
proposal_events_agg AS (
  SELECT
    id_proposal,
    MIN(
      CASE
        WHEN status = 'EVALUATION_STARTED' THEN event_date
      END
    ) AS ts_evaluation_start,
    MIN(
      CASE
        WHEN status IN ('EVALUATION_POSITIVE', 'EVALUATION_POSITIVE_WITH_GUARANTEE') THEN event_date
      END
    ) AS ts_evaluation_positive,
    MIN(
      CASE
        WHEN status = 'DOCS_ANALYSIS' THEN event_date
      END
    ) AS ts_document_sent,
    MIN(
      CASE
        WHEN status = 'APPROVED' THEN event_date
      END
    ) AS ts_credit_approved
  FROM
    proposal_events
  GROUP BY
    id_proposal
),
proposals AS (
  SELECT
    p.id,
    p.id_offer,
    COALESCE(pe.ts_evaluation_start, p.ts_credit_evaluation_first_init) AS ts_evaluation_start,
    COALESCE(pe.ts_evaluation_positive, p.ts_first_credit_evaluation_positive) AS ts_evaluation_positive,
    COALESCE(pe.ts_document_sent, p.ts_tenant_auto_first_doc_sent, p.ts_tenant_first_doc_sent) AS ts_document_sent,
    COALESCE(pe.ts_credit_approved, p.ts_credit_approved_last) AS ts_credit_approved,
    p.has_tenant_sent_documentation
  FROM
    datalake_proposal.proposal AS p
  LEFT JOIN
    proposal_events_agg AS pe
      ON p.id = pe.id_proposal
),
rent_flow_house_listing AS (
  /**
  It was necessary to add some validations related to what's coming from this first CTE (based on the rent flows enriched table) because there
  we can find several bookings, offers, proposals and contracts that not necessarily are following the rules used for this table.
  If we don't apply these filters since the beginning, we can end up having on events like VB already having an id_contract that would not be
  the same contract found when the rent flow event is CS.
  In order to not create any trouble and messy analisys, we decided to filter all ids based on the many possible filters since the beginning.
  **/
  SELECT
    rf.id_rent_flow,
    rf.id_house,
    COALESCE(hl_contract.id_house_listing, hl.id_house_listing) AS id_house_listing,
    h.id_user,
    rf.id_client,
    rf.id_user_agent AS id_agent,
    h.id_region,
    vs.id_schedule AS id_booking,
    vs.id_visit,
    CASE
      WHEN rf.id_offer_context REGEXP '[0-1]{{2}}$' THEN NULL
      WHEN off.ts_first_sent IS NOT NULL OR (off.status IN ('Aprovada', 'ACCEPTED') AND off.ts_analyzed IS NOT NULL) THEN rf.id_offer_context
      ELSE NULL
    END AS id_offer,
    /** Conditions to accept an offer:
      -    Offers that are not pre proposals ("offers" ending with 01)
      -    Offers that were sent (which indicates OS event)
      -    Offers that have status approved and have a timestamp of analysis (which indicates OA event)
    **/
    CASE
      WHEN pp.ts_evaluation_start IS NOT NULL
        OR pp.ts_evaluation_positive IS NOT NULL
        OR pp.ts_document_sent IS NOT NULL
        OR pp.has_tenant_sent_documentation = TRUE
        OR pp.ts_credit_approved IS NOT NULL THEN rf.id_proposal
      ELSE NULL
    END AS id_proposal,
    /** Conditions to accept a proposal:
      -    Proposals that have a credit evaluation first init date (which indicates ES event)
      -    Proposals that have a credit evaluation first positive date (which indicates EP event)
      -    Proposals that have tenant's documentation manual sent or auto doc sent dates (which indicates DS event)
      -    Proposals that have a credit approved last date (which indicates CA event)
    **/
    IF(con.ts_created IS NOT NULL
      OR (con.ts_signed IS NOT NULL AND con.is_active_or_ended = TRUE), rf.id_contract, NULL) AS id_contract,
    /** Conditions to accept a contract:
      -    Contracts that were created and have a timestamp of creation (which indicates CC event)
      -    Contracts that have signed date and status like active or ended (which indicates CS event)
    **/
    IF(h.is_rent_3p_supply, h.uuid_company, NULL) AS uuid_company,
    IF(h.is_rent_3p_supply, h.id_company_hubspot, NULL) AS id_company_hubspot,
    IF(h.is_rent_3p_supply, h.partner_3p_supply, NULL) AS partner_3p_supply,
    COALESCE(h.country_code, 'Undefined') AS country_code
  FROM
    datalake_ebdb_rent_flow.rent_flow AS rf
  JOIN
    datalake_ebdb_listing.house_listing AS hl
      ON hl.id_house = rf.id_house
      AND COALESCE(rf.dt_rent_flow_created, '1900-01-01') BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01')
        AND COALESCE(hl.ts_listing_version_end, NOW())
  LEFT JOIN
    datalake_ebdb_contract.contract AS con
      ON con.id_house = rf.id_house
      AND con.id = rf.id_contract
  LEFT JOIN
    datalake_ebdb_listing.house_listing AS hl_contract
      ON con.id_house = hl_contract.id_house
      AND con.ts_created BETWEEN COALESCE(hl_contract.ts_listing_version_start, '2000-01-01 00:00:00')
        AND COALESCE(hl_contract.ts_listing_version_end, CURRENT_DATE)
  LEFT JOIN
    datalake_ebdb_listing.house AS h
      ON hl.id_house = h.id
  LEFT JOIN
    datalake_ebdb_listing.listing_business_context AS lbc
      ON lbc.id_house = h.id
  LEFT JOIN
    datalake_booking.booking AS bk
      ON bk.id = rf.id_booking
  LEFT JOIN
    datalake_visit.visit_schedules AS vs
      ON vs.id_schedule = bk.id
  LEFT JOIN
    datalake_offer.offer AS off
      ON off.id_offer_context = rf.id_offer_context
  LEFT JOIN
    proposals AS pp
      ON pp.id = rf.id_proposal
  WHERE
    (lbc.business_context = 'RENT'
    OR lbc.business_context IS NULL)
    /** Some properties exists on the House table but not on LBC. In order to keep the same rule/results
        that we have on the fact_listing_rent_flows, we decided to add another filter considering the business context as null
    **/
    AND (
      COALESCE(bk.visit_intent, '') <> 'SALE'
      OR (
        bk.visit_intent = 'SALE'
        AND rf.id_contract IS NOT NULL
      )
    )
),
rent_demand_events AS (
  SELECT --visits_booked
    bk.id AS id_event,
    bk.id AS id_booking,
    bk.id_visit,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    1 AS id_event_type,
    bk.id_visitor AS id_client,
    bk.id_house,
    rf.id_agent,
    bk.id_rent_flow,
    NULL AS id_schedule,
    bk.ts_created AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ts_created) AS year,
    MONTH(ts_created) AS month,
    DAY(ts_created) AS day
  FROM
    datalake_booking.booking AS bk
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = bk.id
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON bk.id_house = hbh.id_house
      AND DATE(bk.ts_created) >= DATE(hbh.ts_started)
      AND DATE(bk.ts_created) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    bk.type = 'Visita'
    AND bk.ts_created IS NOT NULL
  UNION ALL
  SELECT --visits_completed
    bk.id AS id_event,
    bk.id AS id_booking,
    bk.id_visit,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    2 AS id_event_type,
    bk.id_visitor AS id_client,
    bk.id_house,
    rf.id_agent,
    bk.id_rent_flow,
    NULL AS id_schedule,
    bk.ts_booking_utc AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ts_booking_utc) AS year,
    MONTH(ts_booking_utc) AS month,
    DAY(ts_booking_utc) AS day
  FROM
    datalake_booking.booking AS bk
  JOIN
    datalake_visit.visit_schedules AS vs
      ON vs.id_schedule = bk.id
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = bk.id
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON bk.id_house = hbh.id_house
      AND DATE(bk.ts_booking_utc) >= DATE(hbh.ts_started)
      AND DATE(bk.ts_booking_utc) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    vs.is_completed
  UNION ALL
  SELECT --offer_submitted
    off.id_offer_context AS id_event,
    rf.id_booking,
    rf.id_visit,
    off.id_offer_context AS id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    3 AS id_event_type,
    off.id_client,
    off.id_house,
    rf.id_agent,
    off.id_rent_flow,
    NULL AS id_schedule,
    off.ts_first_sent AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ts_first_sent) AS year,
    MONTH(ts_first_sent) AS month,
    DAY(ts_first_sent) AS day
  FROM
    datalake_offer.offer AS off
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_offer = off.id_offer_context
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON off.id_house = hbh.id_house
      AND DATE(off.ts_first_sent) >= DATE(hbh.ts_started)
      AND DATE(off.ts_first_sent) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    ts_first_sent IS NOT NULL
    /** We're not implementing the incremental load for OS since this date information comes from Firestore.
      We noticed that the data is extracted in a certain day but the offer's first sent date is from days before,
      which lead to not being able to load it by incremental load
    **/
  UNION ALL
  SELECT --offer_accepted
    off.id_offer_context AS id_event,
    rf.id_booking,
    rf.id_visit,
    off.id_offer_context AS id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    4 AS id_event_type,
    off.id_client,
    off.id_house,
    rf.id_agent,
    off.id_rent_flow,
    NULL AS id_schedule,
    off.ts_analyzed AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ts_analyzed) AS year,
    MONTH(ts_analyzed) AS month,
    DAY(ts_analyzed) AS day
  FROM
    datalake_offer.offer AS off
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_offer = off.id_offer_context
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON off.id_house = hbh.id_house
      AND DATE(off.ts_analyzed) >= DATE(hbh.ts_started)
      AND DATE(off.ts_analyzed) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    off.status IN ('Aprovada', 'ACCEPTED')
    AND ts_analyzed IS NOT NULL
  UNION ALL
  SELECT --evaluation_started
    pp.id AS id_event,
    rf.id_booking,
    rf.id_visit,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    5 AS id_event_type,
    off.id_client,
    off.id_house,
    rf.id_agent,
    off.id_rent_flow,
    NULL AS id_schedule,
    pp.ts_evaluation_start AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ts_evaluation_start) AS year,
    MONTH(ts_evaluation_start) AS month,
    DAY(ts_evaluation_start) AS day
  FROM
    proposals AS pp
  JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON off.id_house = hbh.id_house
      AND DATE(pp.ts_evaluation_start) >= DATE(hbh.ts_started)
      AND DATE(pp.ts_evaluation_start) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    pp.ts_evaluation_start IS NOT NULL
  UNION ALL
  SELECT --evaluation_positive
    pp.id AS id_event,
    rf.id_booking,
    rf.id_visit,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    6 AS id_event_type,
    off.id_client,
    off.id_house,
    rf.id_agent,
    off.id_rent_flow,
    NULL AS id_schedule,
    pp.ts_evaluation_positive AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(pp.ts_evaluation_positive) AS year,
    MONTH(pp.ts_evaluation_positive) AS month,
    DAY(pp.ts_evaluation_positive) AS day
  FROM
    proposals AS pp
   JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON off.id_house = hbh.id_house
      AND DATE(pp.ts_evaluation_positive) >= DATE(hbh.ts_started)
      AND DATE(pp.ts_evaluation_positive) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    pp.ts_evaluation_positive IS NOT NULL
  UNION ALL
  SELECT --document_sent
    pp.id AS id_event,
    rf.id_booking,
    rf.id_visit,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    7 AS id_event_type,
    COALESCE(off.id_client, rf.id_client) AS id_client,
    COALESCE(off.id_house, rf.id_house) AS id_house,
    rf.id_agent,
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,
    NULL AS id_schedule,
    pp.ts_document_sent AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(pp.ts_document_sent) AS year,
    MONTH(pp.ts_document_sent) AS month,
    DAY(pp.ts_document_sent) AS day
  FROM
    proposals AS pp
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  LEFT JOIN -- We have properties from portability that don't have an offer but have a proposal and contract signed
    datalake_offer.offer AS off
      ON off.id = pp.id_offer
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON COALESCE(off.id_house, rf.id_house) = hbh.id_house
      AND DATE(pp.ts_document_sent) >= DATE(hbh.ts_started)
      AND DATE(pp.ts_document_sent) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    pp.ts_document_sent IS NOT NULL
    OR pp.has_tenant_sent_documentation = TRUE
    /** Some proposals already had a documentation sent (which will be marked by the ts_tenant_first_doc_sent)
        but the boolean flag could turn into false. This behavior is mostly seen from 2022 backwards
    **/
  UNION ALL
  SELECT --credit_approved
    pp.id AS id_event,
    rf.id_booking,
    rf.id_visit,
    rf.id_offer,
    pp.id AS id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    8 AS id_event_type,
    COALESCE(off.id_client, rf.id_client) AS id_client,
    COALESCE(off.id_house, rf.id_house) AS id_house,
    rf.id_agent,
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,
    NULL AS id_schedule,
    pp.ts_credit_approved AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ts_credit_approved) AS year,
    MONTH(ts_credit_approved) AS month,
    DAY(ts_credit_approved) AS day
  FROM
    proposals AS pp
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_proposal = pp.id
  LEFT JOIN   -- We have properties from portability that don't have an offer but have a proposal and contract signed
    datalake_offer.offer AS off
      ON off.id = pp.id_offer
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON COALESCE(off.id_house, rf.id_house) = hbh.id_house
      AND DATE(pp.ts_credit_approved) >= DATE(hbh.ts_started)
      AND DATE(pp.ts_credit_approved) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    pp.ts_credit_approved IS NOT NULL
  UNION ALL
  SELECT --contract_signed
    ct.id AS id_event,
    rf.id_booking,
    rf.id_visit,
    rf.id_offer,
    rf.id_proposal,
    ct.id AS id_contract,
    NULL AS id_advance_payment,
    9 AS id_event_type,
    COALESCE(off.id_client, rf.id_client) AS id_client,
    ct.id_house,
    rf.id_agent,
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,
    NULL AS id_schedule,
    ct.ts_signed AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ts_signed) AS year,
    MONTH(ts_signed) AS month,
    DAY(ts_signed) AS day
  FROM
    datalake_ebdb_contract.contract AS ct
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_contract = ct.id
  LEFT JOIN -- We may have several contracts without offer and proposal (portability). In order to don't lose track of them, we're applying a left join.
    proposals AS pp
      ON ct.id_proposal = pp.id
  LEFT JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON ct.id_house = hbh.id_house
      AND DATE(ct.ts_signed) >= DATE(hbh.ts_started)
      AND DATE(ct.ts_signed) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    ct.ts_signed IS NOT NULL
    AND ct.is_active_or_ended = TRUE
  UNION ALL
  SELECT -- Contract Created (CC)
    ct.id AS id_event,
    rf.id_booking,
    rf.id_visit,
    rf.id_offer,
    rf.id_proposal,
    ct.id AS id_contract,
    NULL AS id_advance_payment,
    10 AS id_event_type,
    COALESCE(off.id_client, rf.id_client) AS id_client,
    ct.id_house,
    rf.id_agent,
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,
    NULL AS id_schedule,
    ct.ts_created AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ct.ts_created) AS year,
    MONTH(ct.ts_created) AS month,
    DAY(ct.ts_created) AS day
  FROM
    datalake_ebdb_contract.contract AS ct
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_contract = ct.id
  LEFT JOIN -- We may have several contracts without offer and proposal (portability). In order to don't lose track of them, we're applying a left join.
    proposals AS pp
      ON ct.id_proposal = pp.id
  LEFT JOIN
    datalake_offer.offer AS off
      ON off.id = pp.id_offer
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON ct.id_house = hbh.id_house
      AND DATE(ct.ts_created) >= DATE(hbh.ts_started)
      AND DATE(ct.ts_created) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    ct.ts_created IS NOT NULL
  UNION ALL
  SELECT --visits_requested
    vsl.id_visit AS id_event,
    vsl.id_schedule AS id_booking,
    vsl.id_visit,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    11 AS id_event_type,
    v.id_visitor AS id_client,
    v.id_house,
    v.id_agent AS id_agent,
    NULL AS id_rent_flow,
    vsl.id_schedule,
    vsl.ts_created AS ts_event,
    rf.id_house_listing,
    NULL AS id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(vsl.ts_created) AS year,
    MONTH(vsl.ts_created) AS month,
    DAY(vsl.ts_created) AS day
  FROM
    datalake_ebdb_clean.visit_status_log AS vsl
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = vsl.id_schedule
  LEFT JOIN
    datalake_ebdb_clean.visit AS v
      ON v.id = vsl.id_visit
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON v.id_house = hbh.id_house
      AND DATE(vsl.ts_created) >= DATE(hbh.ts_started)
      AND DATE(vsl.ts_created) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    vsl.event_type = 'VISIT_REQUESTED'
  UNION ALL
  SELECT --visits_scheduled
    vsl.id_visit AS id_event,
    vsl.id_schedule AS id_booking,
    vsl.id_visit,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    12 AS id_event_type,
    v.id_visitor AS id_client,
    v.id_house,
    v.id_agent AS id_agent,
    rf.id_rent_flow,
    vsl.id_schedule,
    vsl.ts_created AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(vsl.ts_created) AS year,
    MONTH(vsl.ts_created) AS month,
    DAY(vsl.ts_created) AS day
  FROM
    datalake_ebdb_clean.visit_status_log AS vsl
  LEFT JOIN
    datalake_ebdb_clean.visit AS v
      ON v.id = vsl.id_visit
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = vsl.id_schedule
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON v.id_house = hbh.id_house
      AND DATE(vsl.ts_created) >= DATE(hbh.ts_started)
      AND DATE(vsl.ts_created) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    vsl.event_type = 'VISIT_SCHEDULED'
  UNION ALL
  SELECT --visits_rescheduled
    vsl.id_visit AS id_event,
    vsl.id_schedule AS id_booking,
    vsl.id_visit,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    13 AS id_event_type,
    v.id_visitor AS id_client,
    v.id_house,
    v.id_agent AS id_agent,
    rf.id_rent_flow,
    vsl.id_schedule,
    vsl.ts_created AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(vsl.ts_created) AS year,
    MONTH(vsl.ts_created) AS month,
    DAY(vsl.ts_created) AS day
  FROM
    datalake_ebdb_clean.visit_status_log AS vsl
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = vsl.id_schedule
  LEFT JOIN
    datalake_ebdb_clean.visit AS v
      ON v.id = vsl.id_visit
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON v.id_house = hbh.id_house
      AND DATE(vsl.ts_created) >= DATE(hbh.ts_started)
      AND DATE(vsl.ts_created) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    vsl.event_type = 'VISIT_RESCHEDULED'
  UNION ALL
  SELECT --visits_done
    vsl.id_visit AS id_event,
    vsl.id_schedule AS id_booking,
    vsl.id_visit,
    rf.id_offer,
    rf.id_proposal,
    rf.id_contract,
    NULL AS id_advance_payment,
    14 AS id_event_type,
    v.id_visitor AS id_client,
    v.id_house,
    v.id_agent AS id_agent,
    rf.id_rent_flow,
    vsl.id_schedule,
    vsl.ts_created AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(vsl.ts_created) AS year,
    MONTH(vsl.ts_created) AS month,
    DAY(vsl.ts_created) AS day
  FROM
    datalake_ebdb_clean.visit_status_log AS vsl
  JOIN
    rent_flow_house_listing AS rf
      ON rf.id_booking = vsl.id_schedule
  LEFT JOIN
    datalake_ebdb_clean.visit AS v
      ON v.id = vsl.id_visit
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON v.id_house = hbh.id_house
      AND DATE(vsl.ts_created) >= DATE(hbh.ts_started)
      AND DATE(vsl.ts_created) < COALESCE(DATE(hbh.ts_ended), NOW())
  WHERE
    vsl.event_type = 'VISIT_DONE'
  UNION ALL
  SELECT --advance_payment
    ap.id AS id_event,
    rf.id_booking AS id_booking,
    rf.id_visit AS id_visit,
    off.id_offer_context AS id_offer,
    rf.id_proposal AS id_proposal,
    rf.id_contract AS id_contract,
    ap.id AS id_advance_payment,
    CASE
      WHEN ap.status = 'CREATED' THEN 15
      WHEN ap.status = 'PENDING' THEN 16
      WHEN ap.status = 'PROCESSING' THEN 17
      WHEN ap.status = 'PAID' THEN 18
      WHEN ap.status = 'CANCELED' THEN 19
      WHEN ap.status = 'PROCESSING_REFUND' THEN 20
      WHEN ap.status = 'REFUNDED' THEN 21
      WHEN ap.status = 'CHARGEBACK' THEN 22
      WHEN ap.status = 'FINISHED' THEN 23
      WHEN ap.status = 'RETAINED' THEN 24
    END AS id_event_type,
    COALESCE(off.id_client, rf.id_client) AS id_client,
    COALESCE(off.id_house, rf.id_house) AS id_house,
    rf.id_agent,
    COALESCE(off.id_rent_flow, rf.id_rent_flow) AS id_rent_flow,
    NULL AS id_schedule,
    ap.ts_rev AS ts_event,
    rf.id_house_listing,
    rf.id_region,
    rf.id_user,
    hbh.id_user AS id_owner_on_event,
    rf.uuid_company,
    rf.id_company_hubspot,
    rf.partner_3p_supply,
    rf.country_code,
    YEAR(ap.ts_rev) AS year,
    MONTH(ap.ts_rev) AS month,
    DAY(ap.ts_rev) AS day
  FROM
    datalake_rental_transact.advance_payment AS ap
  LEFT JOIN
    datalake_rental_transact_clean.offer AS rto
      ON rto.uuid_offer = ap.uuid_offer
  LEFT JOIN
    datalake_offer.offer AS off
      ON off.id_firestore = rto.id_firestore_offer
  LEFT JOIN
    rent_flow_house_listing AS rf
      ON rf.id_offer = off.id_offer_context
  LEFT JOIN
    datalake_pro_owners.house_b2b_history AS hbh
      ON COALESCE(off.id_house, rf.id_house) = hbh.id_house
      AND DATE(ap.ts_rev) >= DATE(hbh.ts_started)
      AND DATE(ap.ts_rev) < COALESCE(DATE(hbh.ts_ended), NOW())
),
termination_period AS (
  /** We need to understand if a demand event happened during a contract termination process.
    This CTE exists because we have the same listing version with different contracts related (that are active or ended).
    As this is an issue to be investigated and if directly used here would duplicate our events, we decided to use the most
    recent contract.
  **/
  WITH termination_period_ranked AS (
    SELECT
      id_house_listing,
      dt_previous_termination,
      dt_previous_contract_termination,
      ROW_NUMBER() OVER(PARTITION BY id_house_listing ORDER BY ts_contract_created DESC) AS rn
    FROM
      datalake_listing_contracts.listing_contracts
  )
  SELECT
    id_house_listing,
    dt_previous_termination,
    dt_previous_contract_termination
  FROM
    termination_period_ranked
  WHERE
    rn = 1
)
SELECT DISTINCT
  /** As a rent flow may have N times the same booking/proposal/offer appearing related to different demand steps
  (e.g. a same booking related to different offers) and we want to every booking/proposal/offer follow the rules proposed
  on the first CTE, we need to apply a distinct in order to deduplicate it as events start to happen.
  **/
  rde.id_event,
  rde.id_booking,
  rde.id_visit,
  rde.id_offer,
  rde.id_proposal,
  rde.id_advance_payment,
  rde.id_contract,
  rde.id_event_type,
  rde.id_client AS id_tenant_prospect,
  rde.id_house,
  rde.id_agent,
  rde.id_rent_flow,
  rde.id_schedule,
  rde.id_house_listing,
  rde.id_region,
  rde.id_user AS id_owner,
  oc.id_owner_category,
  rde.uuid_company,
  rde.id_company_hubspot,
  rde.partner_3p_supply,
  COALESCE(IF(rde.ts_event BETWEEN t.dt_previous_contract_termination AND t.dt_previous_termination, TRUE, FALSE), FALSE) AS is_during_termination,
  rde.ts_event,
  rde.country_code,
  rde.year AS event_year,
  rde.month AS event_month,
  rde.day AS event_day
FROM
  rent_demand_events AS rde
LEFT JOIN
  termination_period AS t
    ON t.id_house_listing = rde.id_house_listing
LEFT JOIN
  datalake_pro_owners.owner_category AS oc
    ON MAKE_DATE(rde.year, rde.month, rde.day) >= oc.dt_owner_category_started
    AND MAKE_DATE(rde.year, rde.month, rde.day) < COALESCE(oc.dt_owner_category_ended, CURRENT_DATE())
    AND COALESCE(rde.id_owner_on_event, rde.id_user) = oc.id_owner
