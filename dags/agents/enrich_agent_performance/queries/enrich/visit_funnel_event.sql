WITH visit_booking_agent AS (
    SELECT
        vse.id_visit,
        MIN_BY(vse.id_author_user, vse.ts_created) FILTER (
            WHERE vse.event_type IN ('VISIT_RESCHEDULED', 'VISIT_REQUESTED')
                AND vse.channel IN ('AGENT_PWA', 'AGENT_NATIVE')
        ) AS id_user_agent_scheduled_by_agent
    FROM
        datalake_visit.visit_status_events AS vse
    INNER JOIN
        datalake_visit.visits AS v
            ON vse.id_visit = v.id_visit
            AND DATE(v.ts_created) BETWEEN DATE('{reprocess_start_date}') AND DATE('{load_end_date}')
    GROUP BY
        vse.id_visit
),
agent_identity AS (
    SELECT DISTINCT
        id_user,
        uuid_person
    FROM
        datalake_ebdb_agent_events.agent_unified_identity
    WHERE
        id_user IS NOT NULL
),
visit_base AS (
    SELECT
        v.id_visit,
        v.id_visitor,
        v.id_house,
        v.business_context,
        DATE(v.ts_created) AS dt_visit_created,
        v.dt_visit,
        v.id_last_associated_agent AS id_user_last_associated_agent,
        CASE
            WHEN v.visit_request_application_source = 'AGENT_SCHEDULING_LINK'
                OR v.ts_visit_registered IS NOT NULL
                THEN v.id_first_associated_agent
            WHEN vba.id_user_agent_scheduled_by_agent IS NOT NULL
                THEN CAST(vba.id_user_agent_scheduled_by_agent AS BIGINT)
            ELSE NULL
        END AS id_user_agent_vbba,
        pfa.id_user_agent AS id_user_fixed_agent,
        v.nbr_reschedule,
        CAST(v.is_canceled AS INTEGER) AS is_visit_canceled,
        CAST(v.is_completed AS INTEGER) AS is_visit_completed,
        CAST(v.is_unsuccessful AS INTEGER) AS is_visit_unsuccessful,
        CAST(v.is_stalled AS INTEGER) AS is_visit_stalled,
        IF(v.has_finisher_status = FALSE, 1, 0) AS is_visit_not_finished,
        IF(
            v.id_last_associated_agent = pfa.id_user_agent,
            1,
            0
        ) AS is_pfa_visit,
        IF(
            heh.key_location = 'AGENT'
                AND CAST(heh.key_holder_identifier AS BIGINT) = v.id_last_associated_agent
                AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED',
            1,
            0
        ) AS is_crcc_visit,
        IF(v.is_vbba, 1, 0) AS is_vbba_visit,
        IF(
            COALESCE(o_visit.ts_offer_submitted, o_fifty.ts_offer_submitted) IS NOT NULL,
            1,
            0
        ) AS is_offer_submitted,
        IF(
            COALESCE(o_visit.ts_offer_accepted, o_fifty.ts_offer_accepted) IS NOT NULL,
            1,
            0
        ) AS is_offer_accepted,
        IF(
            COALESCE(o_visit.ts_sale_agreement_signed, o_fifty.ts_sale_agreement_signed) IS NOT NULL
                AND COALESCE(o_visit.ts_sale_agreement_canceled, o_fifty.ts_sale_agreement_canceled) IS NULL,
            1,
            0
        ) AS is_agreement_signed,
        v.ts_created AS ts_visit_created,
        v.ts_visit,
        v.ts_visit_rescheduled,
        v.ts_visit_canceled,
        v.ts_visit_done,
        v.ts_visit_unsuccessful,
        v.ts_visit_stalled,
        COALESCE(o_visit.ts_offer_submitted, o_fifty.ts_offer_submitted) AS ts_offer_submitted,
        COALESCE(o_visit.ts_offer_accepted, o_fifty.ts_offer_accepted) AS ts_offer_accepted,
        COALESCE(o_visit.ts_sale_agreement_signed, o_fifty.ts_sale_agreement_signed) AS ts_sale_agreement_signed,
        COALESCE(o_visit.ts_sale_agreement_canceled, o_fifty.ts_sale_agreement_canceled) AS ts_sale_agreement_canceled,
        v.ts_updated AS ts_visit_updated,
        GREATEST(
            v.ts_updated,
            COALESCE(o_visit.ts_updated, v.ts_updated),
            COALESCE(o_fifty.ts_updated, v.ts_updated)
        ) AS ts_source_updated
    FROM
        datalake_visit.visits AS v
    LEFT JOIN
        visit_booking_agent AS vba
            ON v.id_visit = vba.id_visit
    LEFT JOIN
        datalake_ebdb_listing.house AS h
            ON v.id_house = h.id
    LEFT JOIN
        datalake_region.region AS r
            ON h.id_region = r.id
    LEFT JOIN
        datalake_ebdb_agents.preferred_fixed_agent_history AS pfa
            ON v.id_visitor = pfa.id_visitor
            AND r.id_city = pfa.id_region
            AND v.business_context = pfa.business_context
            AND v.ts_created BETWEEN pfa.ts_status_started
                AND COALESCE(pfa.ts_status_ended, TIMESTAMP('{load_end_date}'))
    LEFT JOIN
        datalake_ebdb_listing.house_entrance_history AS heh
            ON v.id_house = heh.id_house
            AND DATE(v.ts_visit) <= DATE('{load_end_date}')
            AND v.ts_visit >= heh.ts_entrance_started
            AND (
                heh.ts_entrance_ended IS NULL
                OR v.ts_visit < heh.ts_entrance_ended
            )
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit
            ON v.id_visit = o_visit.id_visit_external
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_fifty
            ON v.id_visit = o_fifty.id_visit_fifty_external
    WHERE
        DATE(v.ts_created) BETWEEN DATE('{reprocess_start_date}') AND DATE('{load_end_date}')
)
SELECT
    CAST(vb.id_visit AS BIGINT) AS id_visit,
    CAST(vb.id_visitor AS BIGINT) AS id_visitor,
    CAST(vb.id_house AS BIGINT) AS id_house,
    CAST(vb.business_context AS STRING) AS business_context,
    CAST(vb.dt_visit_created AS DATE) AS dt_visit_created,
    CAST(vb.dt_visit AS DATE) AS dt_visit,
    CAST(vb.id_user_last_associated_agent AS BIGINT) AS id_user_last_associated_agent,
    CAST(lai.uuid_person AS STRING) AS uuid_person_last_associated_agent,
    CAST(vb.id_user_agent_vbba AS BIGINT) AS id_user_agent_vbba,
    CAST(vbai.uuid_person AS STRING) AS uuid_person_agent_vbba,
    CAST(vb.id_user_fixed_agent AS BIGINT) AS id_user_fixed_agent,
    CAST(fai.uuid_person AS STRING) AS uuid_person_fixed_agent,
    CAST(1 AS INTEGER) AS is_visit_booked,
    CAST(vb.nbr_reschedule AS INTEGER) AS nbr_reschedule,
    CAST(vb.is_visit_canceled AS INTEGER) AS is_visit_canceled,
    CAST(vb.is_visit_completed AS INTEGER) AS is_visit_completed,
    CAST(vb.is_visit_unsuccessful AS INTEGER) AS is_visit_unsuccessful,
    CAST(vb.is_visit_stalled AS INTEGER) AS is_visit_stalled,
    CAST(vb.is_visit_not_finished AS INTEGER) AS is_visit_not_finished,
    CAST(vb.is_pfa_visit AS INTEGER) AS is_pfa_visit,
    CAST(vb.is_crcc_visit AS INTEGER) AS is_crcc_visit,
    CAST(vb.is_vbba_visit AS INTEGER) AS is_vbba_visit,
    CAST(vb.is_offer_submitted AS INTEGER) AS is_offer_submitted,
    CAST(vb.is_offer_accepted AS INTEGER) AS is_offer_accepted,
    CAST(vb.is_agreement_signed AS INTEGER) AS is_agreement_signed,
    CAST(vb.ts_visit_created AS TIMESTAMP) AS ts_visit_created,
    CAST(vb.ts_visit AS TIMESTAMP) AS ts_visit,
    CAST(vb.ts_visit_rescheduled AS TIMESTAMP) AS ts_visit_rescheduled,
    CAST(vb.ts_visit_canceled AS TIMESTAMP) AS ts_visit_canceled,
    CAST(vb.ts_visit_done AS TIMESTAMP) AS ts_visit_done,
    CAST(vb.ts_visit_unsuccessful AS TIMESTAMP) AS ts_visit_unsuccessful,
    CAST(vb.ts_visit_stalled AS TIMESTAMP) AS ts_visit_stalled,
    CAST(vb.ts_offer_submitted AS TIMESTAMP) AS ts_offer_submitted,
    CAST(vb.ts_offer_accepted AS TIMESTAMP) AS ts_offer_accepted,
    CAST(vb.ts_sale_agreement_signed AS TIMESTAMP) AS ts_sale_agreement_signed,
    CAST(vb.ts_sale_agreement_canceled AS TIMESTAMP) AS ts_sale_agreement_canceled,
    CAST(vb.ts_visit_updated AS TIMESTAMP) AS ts_visit_updated,
    CAST(vb.ts_source_updated AS TIMESTAMP) AS ts_source_updated,
    CAST(YEAR(vb.dt_visit_created) AS INTEGER) AS year,
    CAST(MONTH(vb.dt_visit_created) AS INTEGER) AS month,
    CAST(DAY(vb.dt_visit_created) AS INTEGER) AS day
FROM
    visit_base AS vb
LEFT JOIN
    agent_identity AS lai
        ON vb.id_user_last_associated_agent = lai.id_user
LEFT JOIN
    agent_identity AS vbai
        ON vb.id_user_agent_vbba = vbai.id_user
LEFT JOIN
    agent_identity AS fai
        ON vb.id_user_fixed_agent = fai.id_user
