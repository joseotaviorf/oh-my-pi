WITH bic AS (
  SELECT
    usm.id_snapshot,
    usm.id_user,
    usm.id_last_csi_ticket,
    usm.tenant_journey_step,
    usm.tenant_persona_step,
    usm.landlord_journey_step,
    usm.landlord_persona_step,
    usm.last_bot_csat_answered_score,
    usm.last_human_csat_answered_score,
    usm.bot_csat_detractor_percentage_within_three_months,
    usm.human_csat_detractor_percentage_within_three_months,
    usm.total_csi_tickets_created,
    usm.total_bot_csat_answered,
    usm.total_bot_csat_promoter,
    usm.total_bot_csat_neutral,
    usm.total_bot_csat_detractor,
    usm.avg_bot_csat_score_within_three_months,
    usm.total_bot_csat_detractor_within_three_months,
    usm.total_bot_csat_neutral_within_three_months,
    usm.total_bot_csat_promoter_within_three_months,
    usm.total_bot_csat_answered_within_three_months,
    usm.total_human_csat_answered,
    usm.total_human_csat_promoter,
    usm.total_human_csat_neutral,
    usm.total_human_csat_detractor,
    usm.avg_human_csat_score_within_three_months,
    usm.total_human_csat_detractor_within_three_months,
    usm.total_human_csat_neutral_within_three_months,
    usm.total_human_csat_promoter_within_three_months,
    usm.total_human_csat_answered_within_three_months,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_bookings
        WHEN usm.is_landlord IS TRUE THEN ljs.total_bookings
        ELSE NULL
    END AS total_bookings,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_reservations
        WHEN usm.is_landlord IS TRUE THEN ljs.total_reservations
        ELSE NULL
    END AS total_reservations,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_canceled_bookings
        WHEN usm.is_landlord IS TRUE THEN ljs.total_canceled_bookings
        ELSE NULL
    END AS total_canceled_bookings,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_completed_visits
        WHEN usm.is_landlord IS TRUE THEN ljs.total_completed_visits
        ELSE NULL
    END AS total_completed_visits,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_sent_offers
        WHEN usm.is_landlord IS TRUE THEN ljs.total_sent_offers
        ELSE NULL
    END AS total_sent_offers,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_accepted_offers
        WHEN usm.is_landlord IS TRUE THEN ljs.total_accepted_offers
        ELSE NULL
    END AS total_accepted_offers,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_rejected_offers
        WHEN usm.is_landlord IS TRUE THEN ljs.total_rejected_offers
        ELSE NULL
    END AS total_rejected_offers,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_started_evaluation_proposals
        WHEN usm.is_landlord IS TRUE THEN ljs.total_started_evaluation_proposals
        ELSE NULL
    END AS total_started_evaluation_proposals,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_approved_evaluation_proposals
        WHEN usm.is_landlord IS TRUE THEN ljs.total_approved_evaluation_proposals
        ELSE NULL
    END AS total_approved_evaluation_proposals,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_sent_document_proposals
        WHEN usm.is_landlord IS TRUE THEN ljs.total_sent_document_proposals
        ELSE NULL
    END AS total_sent_document_proposals,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_approved_credit_proposals
        WHEN usm.is_landlord IS TRUE THEN ljs.total_approved_credit_proposals
        ELSE NULL
    END AS total_approved_credit_proposals,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_rejected_proposals
        WHEN usm.is_landlord IS TRUE THEN ljs.total_rejected_proposals
        ELSE NULL
    END AS total_rejected_proposals,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_signed_contracts
        WHEN usm.is_landlord IS TRUE THEN ljs.total_signed_contracts
        ELSE NULL
    END AS total_signed_contracts,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_active_contracts
        WHEN usm.is_landlord IS TRUE THEN ljs.total_active_contracts
        ELSE NULL
    END AS total_active_contracts,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_finished_contracts
        WHEN usm.is_landlord IS TRUE THEN ljs.total_finished_contracts
        ELSE NULL
    END AS total_finished_contracts,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.total_active_termination_contracts
        WHEN usm.is_landlord IS TRUE THEN ljs.total_active_termination_contracts
        ELSE NULL
    END AS total_active_termination_contracts,
    usm.app_version,
    usm.is_pp_multi,
    usm.is_tenant,
    usm.is_broker,
    usm.is_landlord,
    usm.is_photographer,
    usm.is_tenant_offboarding,
    usm.is_tenant_ongoing,
    usm.is_tenant_onboarding,
    usm.is_tenant_contract_to_entrance,
    usm.is_tenant_visits_to_offer,
    usm.is_tenant_listing_and_search,
    usm.is_tenant_pre_contract,
    usm.is_tenant_post_contract,
    usm.is_landlord_offboarding,
    usm.is_landlord_ongoing,
    usm.is_landlord_onboarding,
    usm.is_landlord_contract_to_entrance,
    usm.is_landlord_visits_to_offer,
    usm.is_landlord_listing_and_search,
    usm.is_landlord_pre_contract,
    usm.is_landlord_post_contract,
    usm.is_blocked,
    usm.has_created_csi_ticket,
    usm.has_answered_human_csat_within_three_months,
    usm.has_answered_bot_csat_within_three_months,
    usm.has_app_installed,
    ljs.has_published_listings,
    ljs.has_pending_listings_only,
    ljs.has_opted_out_listings_only,
    tjs.has_searched_house,

    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_funnel_step
        WHEN usm.is_landlord IS TRUE THEN ljs.has_funnel_step
        ELSE NULL
    END AS has_funnel_step,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_booked_visit
        WHEN usm.is_landlord IS TRUE THEN ljs.has_booked_visit
        ELSE NULL
    END AS has_booked_visit,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_completed_visit
        WHEN usm.is_landlord IS TRUE THEN ljs.has_completed_visit
        ELSE NULL
    END AS has_completed_visit,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_sent_offer
        WHEN usm.is_landlord IS TRUE THEN ljs.has_sent_offer
        ELSE NULL
    END AS has_sent_offer,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_offer_approved
        WHEN usm.is_landlord IS TRUE THEN ljs.has_offer_approved
        ELSE NULL
    END AS has_offer_approved,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_started_evaluation
        WHEN usm.is_landlord IS TRUE THEN ljs.has_started_evaluation
        ELSE NULL
    END AS has_started_evaluation,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_evaluation_approved
        WHEN usm.is_landlord IS TRUE THEN ljs.has_evaluation_approved
        ELSE NULL
    END AS has_evaluation_approved,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_sent_doc
        WHEN usm.is_landlord IS TRUE THEN ljs.has_sent_doc
        ELSE NULL
    END AS has_sent_doc,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_credit_approved
        WHEN usm.is_landlord IS TRUE THEN ljs.has_credit_approved
        ELSE NULL
    END AS has_credit_approved,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_active_contract
        WHEN usm.is_landlord IS TRUE THEN ljs.has_active_contract
        ELSE NULL
    END AS has_active_contract,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_finished_contract
        WHEN usm.is_landlord IS TRUE THEN ljs.has_finished_contract
        ELSE NULL
    END AS has_finished_contract,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.has_active_termination
        WHEN usm.is_landlord IS TRUE THEN ljs.has_active_termination
        ELSE NULL
    END AS has_active_termination,
    usm.dt_user_birth,
    usm.ts_user_updated,
    usm.ts_user_created,
    usm.ts_most_recent_csi_ticket_creation_date,
    usm.ts_most_recent_csi_ticket_solved_date,
    usm.ts_last_bot_csat_created,
    usm.ts_last_human_csat_created,
    usm.ts_last_app_installed,
    tjs.ts_last_house_searching,
    ljs.ts_last_listing_updated,

    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_booking
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_booking
    END AS ts_last_booking,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_reservation
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_reservation
    END AS ts_last_reservation,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_booking_canceled
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_booking_canceled
    END AS ts_last_booking_canceled,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_visiting
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_visiting
    END AS ts_last_visiting,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_offer_sending
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_offer_sending
    END AS ts_last_offer_sending,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_offer_rejected
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_offer_rejected
    END AS ts_last_offer_rejected,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_offer_approval
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_offer_approval
    END AS ts_last_offer_approval,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_evaluation_start
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_evaluation_start
    END AS ts_last_evaluation_start,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_evaluation_approval
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_evaluation_approval
    END AS ts_last_evaluation_approval,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_doc_sending
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_doc_sending
    END AS ts_last_doc_sending,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_credit_approval
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_credit_approval
    END AS ts_last_credit_approval,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_proposal_rejected
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_proposal_rejected
    END AS ts_last_proposal_rejected,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_contract_signed
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_contract_signed
    END AS ts_last_contract_signed,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_termination_created
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_termination_created
    END AS ts_last_termination_created,
    CASE
        WHEN usm.is_tenant IS TRUE THEN tjs.ts_last_termination_finished
        WHEN usm.is_landlord IS TRUE THEN ljs.ts_last_termination_finished
    END AS ts_last_termination_finished
  FROM
    datalake_ss_logic_model.user_ss_metrics AS usm
  LEFT JOIN
    datalake_tenant_journey.tenant_journey_step AS tjs
      ON tjs.id_client = usm.id_user
      AND tjs.id_snapshot = usm.id_snapshot
  LEFT JOIN
    datalake_landlord_journey.landlord_journey_step AS ljs
      ON ljs.id_owner = usm.id_user
      AND ljs.id_snapshot = usm.id_snapshot
  WHERE
    usm.id_snapshot = DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd')
    OR usm.id_snapshot = DATE_FORMAT(DATE_SUB('{year}-{month}-{day}', 1), 'yyyyMMdd')
)
SELECT
  * EXCEPT(id_snapshot)
FROM
  bic
WHERE
  id_snapshot = DATE_FORMAT(DATE('{year}-{month}-{day}'), 'yyyyMMdd')
  AND app_version IS NOT NULL
  AND (
    app_version LIKE '8.117%'
    OR app_version LIKE '8.118%'
    OR app_version LIKE '8.119%'
  )
