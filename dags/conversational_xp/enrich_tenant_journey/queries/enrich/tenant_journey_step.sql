-- Only for finished terminations, retrieve the correct finished date
WITH terminations_finished AS (
  SELECT
    ta.id,
    MIN(ta.rev) AS min_rev,
    MIN(ta.ts_updated) AS ts_termination_finished
  FROM
    datalake_terminator_clean.termination_aud AS ta
  WHERE
    ta.status = 'DONE'
  GROUP BY 1
),
-- Last reservation by house and tenant
reservations AS (
  SELECT
    r.id_reservation,
    r.status,
    r.ts_created,
    r.id_house,
    r.id_tenant,
    MAX(r.id_reservation) OVER (PARTITION BY r.id_house, r.id_tenant) AS max_id,
    COUNT(1) OVER (PARTITION BY r.id_house, r.id_tenant) AS reservation_attempts
  FROM
    datalake_kill_queue.reservation AS r
),
-- Last proposal status and revision date
rejected_proposals AS (
  WITH proposal_timestamp (
    SELECT
      pa.id_proposal,
      pa.status,
      MIN(CAST(FROM_UNIXTIME(CAST(ure.ts_revision AS BIGINT)/1000) AS TIMESTAMP)) AS ts_revision
    FROM
      datalake_ebdb_clean.proposal_aud AS pa
    INNER JOIN
      datalake_ebdb_clean.user_revision_entity AS ure
        ON pa.rev = ure.id
    GROUP BY 1, 2
  )
  SELECT
    pt.id_proposal,
    pt.status,
    pt.ts_revision
  FROM
    proposal_timestamp AS pt
  QUALIFY
    ROW_NUMBER() OVER(
      PARTITION BY pt.id_proposal
      ORDER BY pt.ts_revision DESC
    ) = 1
),
-- Amplitude Last Search Rent Events by id_user
amplitude_last_search_events AS (
  SELECT
    REGEXP_REPLACE(ssle.id_user, "\\.", "") AS id_user,
    MAX(ssle.ts_event) AS ts_event
  FROM
    datalake_amplitude_page_viewed_events.schedule_search_listing_events AS ssle
  WHERE
    COALESCE(ssle.business_context, 'rent') = 'rent'
    AND ssle.id_user IS NOT NULL
    AND REGEXP_REPLACE(ssle.id_user, "\\.", "") RLIKE '^[0-9]*$'
  GROUP BY 1
),
-- CTE to retrieve the timestamp for specific events, such as, canceled booking, rejected offers, rejected credits, termination created and finished.
tenant_events_timestamp AS (
  SELECT DISTINCT
    rde.id_tenant_prospect AS id_client,
    rde.id_event,
    rde.id_event_type,
    rde.ts_event,
    rde.id_booking,
    r.id_reservation,
    rde.id_offer,
    rde.id_proposal,
    rde.id_contract,
    tm.id AS id_termination,
    bk.status AS booking_status,
    r.status AS reservation_status,
    off.status AS offer_status,
    rp.status AS proposal_status,
    ct.status AS contract_status,
    tm.status AS termination_status,
    ROW_NUMBER() OVER(
      PARTITION BY rde.id_tenant_prospect, rde.id_event_type
      ORDER BY ts_event DESC
    ) AS order_event,
    bk.ts_first_canceled AS ts_booking_canceled,
    off.ts_analyzed AS ts_offer_rejected,
    r.ts_created AS ts_reservation_created,
    rp.ts_revision AS ts_proposal_rejected,
    tm.ts_created AS ts_termination_created,
    -- Rule applied in the contract_termination table, in this case, considering the negotiation update date
    CASE
      WHEN rde.id_event_type = 9
        AND tf.ts_termination_finished <= '2020-07-07' THEN neg.ts_updated
      WHEN rde.id_event_type = 9
        AND tf.ts_termination_finished > '2020-07-07' THEN tf.ts_termination_finished
    END AS ts_termination_finished
  FROM
    datalake_rent_demand_events.rent_demand_events AS rde
  -- Since the id_event_type 9 consider only Ativo and Finalizado contracts, there is no need to check others status in the contract table
  LEFT JOIN
    datalake_ebdb_clean.contract AS ct
      ON ct.id = rde.id_contract
      AND ct.status IN ('Ativo', 'Finalizado')
  LEFT JOIN
    datalake_booking.booking AS bk
      ON bk.id = rde.id_booking
  LEFT JOIN
    datalake_offer.offer AS off
      ON off.id_offer_context = rde.id_offer
      AND off.status IN ('Rejeitada', 'REJECTED')
  LEFT JOIN
    rejected_proposals AS rp
      ON rp.id_proposal = rde.id_proposal
      AND rp.status = 'Rejeitada'
  LEFT JOIN
    datalake_terminator_clean.termination AS tm
      ON tm.id_contract = rde.id_contract
  LEFT JOIN
    terminations_finished AS tf
      ON tm.id = tf.id
      AND tm.status = 'DONE'
  LEFT JOIN
    datalake_terminator_clean.negotiation AS neg
      ON tm.id = neg.id_termination
  LEFT JOIN
    reservations AS r
      ON r.id_tenant = rde.id_tenant_prospect
      AND r.id_house = rde.id_house
      AND rde.id_event_type = 4
      AND r.max_id = r.id_reservation
),
tenant_journey_agg AS (
  SELECT
    COALESCE(tet.id_client, alse.id_user) AS id_client,
    MIN(
      CASE
        WHEN alse.id_user IS NOT NULL
          AND alse.ts_event IS NOT NULL THEN DATEDIFF(DATE('{year}-{month}-{day}'), alse.ts_event)
      END
    ) AS total_days_since_last_house_searching,
    -- The order_event is used to retrieve only the last event for a respective type
    MAX(
      CASE
        WHEN tet.id_event_type = 1
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_booking,
    MIN(
      CASE
        WHEN tet.ts_reservation_created IS NOT NULL THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_reservation_created)
      END
    ) AS total_days_since_last_reservation_created,
    MIN(
      CASE
        WHEN tet.id_event_type = 1
          AND tet.booking_status = 'Cancelado'
          AND tet.ts_booking_canceled IS NOT NULL THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_booking_canceled)
      END
    ) AS total_days_since_last_canceled_booking,
    MAX(
      CASE
        WHEN tet.id_event_type = 2
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_visiting,
    MAX(
      CASE
        WHEN tet.id_event_type = 3
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_offer_sending,
    -- In this case, we are not using the order_event, because we are interest in the last offer rejected date for all event_type equal to 3 (offer submitted)
    MIN(
      CASE
        WHEN tet.id_event_type = 3
          AND tet.offer_status IN ('Rejeitada', 'REJECTED')
          AND tet.ts_offer_rejected IS NOT NULL THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_offer_rejected)
      END
    ) AS total_days_since_last_offer_rejected,
    MAX(
      CASE
        WHEN tet.id_event_type = 4
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_offer_approval,
    MAX(
      CASE
        WHEN tet.id_event_type = 5
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_evaluation_start,
    MAX(
      CASE
        WHEN tet.id_event_type = 6
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_evaluation_approval,
    MAX(
      CASE
        WHEN tet.id_event_type = 7
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_doc_sending,
    MAX(
      CASE
        WHEN tet.id_event_type = 8
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_credit_approval,
    MIN(
      CASE
        WHEN tet.id_proposal IS NOT NULL
          AND tet.proposal_status = 'Rejeitada'
          AND tet.ts_proposal_rejected IS NOT NULL THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_proposal_rejected)
      END
    ) AS total_days_since_last_proposal_rejected,
    MAX(
      CASE
        WHEN tet.id_event_type = 9
          AND tet.order_event = 1 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event)
      END
    ) AS total_days_since_last_contract_signing,
    MIN(
      CASE
        WHEN tet.id_event_type = 9 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_termination_created)
      END
    ) AS total_days_since_last_termination_creation,
    MIN(
      CASE
        WHEN tet.id_event_type = 9 THEN DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_termination_finished)
      END
    ) AS total_days_since_last_termination_finished,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 1 THEN tet.id_booking
        END
    ) AS total_bookings,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.ts_reservation_created IS NOT NULL THEN tet.id_reservation
        END
    ) AS total_reservations,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 1
            AND tet.booking_status = 'Cancelado' THEN tet.id_booking
        END
    ) AS total_canceled_bookings,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 2 THEN tet.id_booking
        END
    ) AS total_completed_visits,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 3 THEN tet.id_offer
        END
    ) AS total_sent_offers,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 4 THEN tet.id_offer
        END
    ) AS total_accepted_offers,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 3
            AND tet.offer_status IN ('Rejeitada', 'REJECTED') THEN tet.id_offer
        END
    ) AS total_rejected_offers,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 5 THEN tet.id_proposal
        END
    ) AS total_started_evaluation_proposals,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 6 THEN tet.id_proposal
        END
    ) AS total_approved_evaluation_proposals,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 7 THEN tet.id_proposal
        END
    ) AS total_sent_document_proposals,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 8 THEN tet.id_proposal
        END
    ) AS total_approved_credit_proposals,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_proposal IS NOT NULL
            AND tet.proposal_status = 'Rejeitada' THEN tet.id_proposal
      END
    ) AS total_rejected_proposals,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 9 THEN tet.id_contract
        END
    ) AS total_signed_contracts,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 9
            AND tet.contract_status = 'Ativo' THEN tet.id_contract
        END
    ) AS total_active_contracts,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 9 AND tet.contract_status = 'Ativo' AND DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event) <= 40 THEN tet.id_contract
        END
    ) AS total_onboarding_active_contracts,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 9 AND tet.contract_status = 'Ativo' AND DATEDIFF(DATE('{year}-{month}-{day}'), tet.ts_event) > 40 THEN tet.id_contract
        END
    ) AS total_ongoing_active_contracts,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 9
            AND tet.contract_status = 'Finalizado' THEN tet.id_contract
        END
    ) AS total_finished_contracts,
    COUNT(
      DISTINCT
        CASE
          WHEN tet.id_event_type = 9
            AND tet.termination_status NOT IN ('DONE', 'CANCELED') THEN tet.id_contract
        END
    ) AS total_active_termination_contracts,
    MAX(
      CASE
        WHEN alse.id_user IS NOT NULL THEN TRUE
        ELSE FALSE
      END
    ) AS has_searched_house,
    MAX(
      CASE
        WHEN tet.id_client IS NOT NULL THEN TRUE
        ELSE FALSE
      END
    ) AS has_funnel_step,
    MAX(
      CASE
        WHEN tet.id_event_type = 1 THEN TRUE
        ELSE FALSE
      END
    ) AS has_booked_visit,
    MAX(
      CASE
        WHEN tet.id_event_type = 2 THEN TRUE
        ELSE FALSE
      END
    ) AS has_completed_visit,
    MAX(
      CASE
        WHEN tet.id_event_type = 3 THEN TRUE
        ELSE FALSE
      END
    ) AS has_sent_offer,
    MAX(
      CASE
        WHEN tet.id_event_type = 4 THEN TRUE
        ELSE FALSE
      END
    ) AS has_offer_approved,
    MAX(
      CASE
        WHEN tet.id_event_type = 5 THEN TRUE
        ELSE FALSE
      END
    ) AS has_started_evaluation,
    MAX(
      CASE
        WHEN tet.id_event_type = 6 THEN TRUE
        ELSE FALSE
      END
    ) AS has_evaluation_approved,
    MAX(
      CASE
        WHEN tet.id_event_type = 7 THEN TRUE
        ELSE FALSE
      END
    ) AS has_sent_doc,
    MAX(
      CASE
        WHEN tet.id_event_type = 8 THEN TRUE
        ELSE FALSE
      END
    ) AS has_credit_approved,
    MAX(
      CASE
        WHEN tet.id_event_type = 9
          AND tet.contract_status = 'Ativo' THEN TRUE
        ELSE FALSE
      END
    ) AS has_active_contract,
    MAX(
      CASE
        WHEN tet.id_event_type = 9
          AND tet.contract_status = 'Finalizado' THEN TRUE
        ELSE FALSE
      END
    ) AS has_finished_contract,
    MAX(
      CASE
        WHEN tet.id_event_type = 9
          AND tet.termination_status NOT IN ('DONE', 'CANCELED') THEN TRUE
        ELSE FALSE
      END
    ) AS has_active_termination,
    MAX(
      CASE
        WHEN alse.id_user IS NOT NULL THEN alse.ts_event
      END
    ) AS ts_last_house_searching,
    MAX(
      CASE
        WHEN tet.id_event_type = 1
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_booking,
    MAX(
      CASE
        WHEN tet.id_reservation IS NOT NULL THEN tet.ts_reservation_created
      END
    ) AS ts_last_reservation,
    MAX(
      CASE
        WHEN tet.id_event_type = 1
          AND tet.booking_status = 'Cancelado' THEN tet.ts_booking_canceled
      END
    ) AS ts_last_booking_canceled,
    MAX(
      CASE
        WHEN tet.id_event_type = 2
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_visiting,
    MAX(
      CASE
        WHEN tet.id_event_type = 3
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_offer_sending,
    MAX(
      CASE
        WHEN tet.id_event_type = 3
          AND tet.offer_status IN ('Rejeitada', 'REJECTED') THEN tet.ts_offer_rejected
        END
    ) AS ts_last_offer_rejected,
    MAX(
      CASE
        WHEN tet.id_event_type = 4
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_offer_approval,
    MAX(
      CASE
        WHEN tet.id_event_type = 5
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_evaluation_start,
    MAX(
      CASE
        WHEN tet.id_event_type = 6
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_evaluation_approval,
    MAX(
      CASE
        WHEN tet.id_event_type = 7
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_doc_sending,
    MAX(
        CASE
          WHEN tet.id_event_type = 8
            AND tet.order_event = 1 THEN tet.ts_event
        END
    ) AS ts_last_credit_approval,
    MAX(
      CASE
        WHEN tet.id_proposal IS NOT NULL
          AND tet.proposal_status = 'Rejeitada' THEN tet.ts_proposal_rejected
      END
    ) AS ts_last_proposal_rejected,
    MAX(
      CASE
        WHEN tet.id_event_type = 9
          AND tet.order_event = 1 THEN tet.ts_event
      END
    ) AS ts_last_contract_signed,
    MAX(
      CASE
        WHEN tet.id_event_type = 9 THEN tet.ts_termination_created
      END
    ) AS ts_last_termination_created,
    MAX(
      CASE
        WHEN tet.id_event_type = 9 THEN tet.ts_termination_finished
      END
    ) AS ts_last_termination_finished
  FROM
    tenant_events_timestamp AS tet
  FULL OUTER JOIN
    amplitude_last_search_events AS alse
      ON tet.id_client = alse.id_user
  GROUP BY 1
),
step_journey AS (
  SELECT
    *,
    COALESCE(total_days_since_last_house_searching <= 40, FALSE) AS is_listing_and_search,
    COALESCE(
      total_days_since_last_booking <= 40
        OR total_days_since_last_canceled_booking <= 40
        OR total_days_since_last_visiting <= 40
        OR total_days_since_last_offer_sending <= 40
        OR total_days_since_last_offer_rejected <= 40
        OR total_days_since_last_reservation_created <= 40
        OR total_days_since_last_offer_approval <= 40, FALSE
    ) AS is_visits_to_offer,
    COALESCE(
      total_days_since_last_evaluation_start <= 40
        OR total_days_since_last_evaluation_approval <= 40
        OR total_days_since_last_doc_sending <= 40
        OR total_days_since_last_credit_approval <= 40
        OR total_days_since_last_proposal_rejected <= 40, FALSE
    ) AS is_contract_to_entrance,
    COALESCE(
      total_onboarding_active_contracts > 0, FALSE
    ) AS is_onboarding,
    COALESCE(
      total_ongoing_active_contracts > 0, FALSE
    ) AS is_ongoing,
    has_active_termination AS is_offboarding
  FROM
    tenant_journey_agg
)
SELECT
  DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd') AS id_snapshot,
  sj.id_client,
  CASE
    WHEN sj.is_offboarding THEN 'Offboarding'
    WHEN sj.is_ongoing THEN 'Ongoing'
    WHEN sj.is_onboarding THEN 'Onboarding'
    WHEN sj.is_contract_to_entrance THEN 'Contract to Entrance'
    WHEN sj.is_visits_to_offer THEN 'Visits to Offer'
    WHEN sj.is_listing_and_search THEN 'Listing and Search'
    ELSE 'Default'
  END AS journey_step,
  CASE
    WHEN sj.is_offboarding
      OR sj.is_ongoing
      OR sj.is_onboarding THEN 'Post_Contract'
    WHEN sj.is_contract_to_entrance
      OR sj.is_visits_to_offer
      OR sj.is_listing_and_search THEN 'Pre_Contract'
    ELSE 'Not_Apply'
  END AS persona_step,
  IF(sj.total_days_since_last_house_searching < 0, 0, sj.total_days_since_last_house_searching) AS total_days_since_last_house_searching,
  IF(sj.total_days_since_last_booking < 0, 0, sj.total_days_since_last_booking) AS total_days_since_last_booking,
  IF(sj.total_days_since_last_reservation_created < 0, 0, sj.total_days_since_last_reservation_created) AS total_days_since_last_reservation_created,
  IF(sj.total_days_since_last_canceled_booking < 0, 0, sj.total_days_since_last_canceled_booking) AS total_days_since_last_canceled_booking,
  IF(sj.total_days_since_last_visiting < 0, 0, sj.total_days_since_last_visiting) AS total_days_since_last_visiting,
  IF(sj.total_days_since_last_offer_sending < 0, 0, sj.total_days_since_last_offer_sending) AS total_days_since_last_offer_sending,
  IF(sj.total_days_since_last_offer_rejected < 0, 0, sj.total_days_since_last_offer_rejected) AS total_days_since_last_offer_rejected,
  IF(sj.total_days_since_last_offer_approval < 0, 0, sj.total_days_since_last_offer_approval) AS total_days_since_last_offer_approval,
  IF(sj.total_days_since_last_evaluation_start < 0, 0, sj.total_days_since_last_evaluation_start) AS total_days_since_last_evaluation_start,
  IF(sj.total_days_since_last_evaluation_approval < 0, 0, sj.total_days_since_last_evaluation_approval) AS total_days_since_last_evaluation_approval,
  IF(sj.total_days_since_last_doc_sending < 0, 0, sj.total_days_since_last_doc_sending) AS total_days_since_last_doc_sending,
  IF(sj.total_days_since_last_credit_approval < 0, 0, sj.total_days_since_last_credit_approval) AS total_days_since_last_credit_approval,
  IF(sj.total_days_since_last_proposal_rejected < 0, 0, sj.total_days_since_last_proposal_rejected) AS total_days_since_last_proposal_rejected,
  IF(sj.total_days_since_last_contract_signing < 0, 0, sj.total_days_since_last_contract_signing) AS total_days_since_last_contract_signing,
  IF(sj.total_days_since_last_termination_creation < 0, 0, sj.total_days_since_last_termination_creation) AS total_days_since_last_termination_creation,
  IF(sj.total_days_since_last_termination_finished < 0, 0, sj.total_days_since_last_termination_finished) AS total_days_since_last_termination_finished,
  sj.total_bookings,
  sj.total_reservations,
  sj.total_canceled_bookings,
  sj.total_completed_visits,
  sj.total_sent_offers,
  sj.total_accepted_offers,
  sj.total_rejected_offers,
  sj.total_started_evaluation_proposals,
  sj.total_approved_evaluation_proposals,
  sj.total_sent_document_proposals,
  sj.total_approved_credit_proposals,
  sj.total_rejected_proposals,
  sj.total_signed_contracts,
  sj.total_active_contracts,
  sj.total_finished_contracts,
  sj.total_active_termination_contracts,
  sj.has_searched_house,
  sj.has_funnel_step,
  sj.has_booked_visit,
  sj.has_completed_visit,
  sj.has_sent_offer,
  sj.has_offer_approved,
  sj.has_started_evaluation,
  sj.has_evaluation_approved,
  sj.has_sent_doc,
  sj.has_credit_approved,
  sj.has_active_contract,
  sj.has_finished_contract,
  sj.has_active_termination,
  sj.is_offboarding,
  sj.is_ongoing,
  sj.is_onboarding,
  sj.is_contract_to_entrance,
  sj.is_visits_to_offer,
  sj.is_listing_and_search,
  CASE
    WHEN sj.is_offboarding
      OR sj.is_ongoing
      OR sj.is_onboarding THEN TRUE
    ELSE FALSE
  END AS is_post_contract,
  CASE
    WHEN sj.is_contract_to_entrance
      OR sj.is_visits_to_offer
      OR sj.is_listing_and_search THEN TRUE
    ELSE FALSE
  END AS is_pre_contract,
  sj.ts_last_house_searching,
  sj.ts_last_booking,
  sj.ts_last_reservation,
  sj.ts_last_booking_canceled,
  sj.ts_last_visiting,
  sj.ts_last_offer_sending,
  sj.ts_last_offer_rejected,
  sj.ts_last_offer_approval,
  sj.ts_last_evaluation_start,
  sj.ts_last_evaluation_approval,
  sj.ts_last_doc_sending,
  sj.ts_last_credit_approval,
  sj.ts_last_proposal_rejected,
  sj.ts_last_contract_signed,
  sj.ts_last_termination_created,
  sj.ts_last_termination_finished,
  {year} AS year,
  {month} AS month,
  {day} AS day
FROM
  step_journey AS sj
