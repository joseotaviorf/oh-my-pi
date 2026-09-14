WITH visit_updated AS ( -- All visits updated will be considered to recalculate the metrics for each agent + date
    SELECT DISTINCT
        COALESCE(va.id_agent, fvs.sk_last_associated_agent) AS id_user_agent,
        DATE(dv.dt_created) AS date_ref
    FROM
        dw_visit.fact_visits AS fvs
    JOIN
        dw_visit.dim_visit AS dv
            ON fvs.sk_visit = dv.sk_visit
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit
            ON fvs.sk_visit = o_visit.id_visit_external
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit_fifty
            ON fvs.sk_visit = o_visit_fifty.id_visit_fifty_external
    -- This is used to get all agents related to the visit and update the metrics considering the last associated agent
    LEFT JOIN
        datalake_ebdb_clean.visit_aud AS va
            ON fvs.sk_visit = va.id_visit
    WHERE
        GREATEST(
            DATE(dv.dt_updated),
            DATE(o_visit.ts_updated),
            DATE(o_visit_fifty.ts_updated)
        ) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
        AND dv.business_context = 'SALE'
),
allow_demand_visit_base AS ( -- All agents that are allowed to receive demand visits will be considered to calculate the metrics for each agent + date (if the agent does not receive demand visits, the metrics will be 0)
    SELECT DISTINCT
        uuid_person,
        dt_ref AS date_ref
    FROM
        dw_agent.fact_agent_daily
    WHERE
        is_allow_demand_visit
        AND dt_ref BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
updated_base AS (
    SELECT DISTINCT
        du.uuid_person,
        vu.date_ref
    FROM
        visit_updated AS vu
    JOIN
        dw_public.dim_user AS du
            ON vu.id_user_agent = du.sk_user
    UNION
    SELECT
        uuid_person,
        date_ref
    FROM
        allow_demand_visit_base
),
visit_funnel_metrics AS ( -- Metrics for each agent + date (based on last associated agent)
    SELECT
        ub.uuid_person,
        ub.date_ref,
        SUM(fvs.num_visit_booked) AS total_visit,
        SUM(fvs.nbr_reschedule) AS total_rescheduled,
        SUM(fvs.num_visit_canceled) AS total_visit_canceled,
        SUM(fvs.num_visit_completed) AS total_visit_completed,
        SUM(fvs.num_visit_unsuccessful) AS total_visit_unsuccessful,
        SUM(fvs.num_visit_stalled) AS total_visit_stalled,
        SUM(IF(dv.has_visit_finisher_status = False, 1, 0)) AS total_visit_not_finished,
        SUM(IF(COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL, 1, 0)) AS total_offer_submitted,
        SUM(IF(COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL, 1, 0)) AS total_offer_accepted,
        SUM(IF(COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL, 1, 0)) AS total_agreement_signed,
        SUM(IF(fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_visit_pfa,
        SUM(IF(fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, fvs.nbr_reschedule, 0)) AS total_rescheduled_pfa,
        SUM(IF(dv.is_visit_canceled AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_visit_canceled_pfa,
        SUM(IF(dv.is_visit_completed AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_visit_completed_pfa,
        SUM(IF(dv.is_visit_unsuccessful AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_visit_unsuccessful_pfa,
        SUM(IF(dv.is_visit_stalled AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_visit_stalled_pfa,
        SUM(IF(dv.has_visit_finisher_status = False AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_visit_not_finished_pfa,
        SUM(IF(COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_offer_submitted_pfa,
        SUM(IF(COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_offer_accepted_pfa,
        SUM(IF(COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL AND fvs.sk_last_associated_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_agreement_signed_pfa,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_visit_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', fvs.nbr_reschedule, 0)) AS total_rescheduled_crcc,
        SUM(IF(dv.is_visit_canceled AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_visit_canceled_crcc,
        SUM(IF(dv.is_visit_completed AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_visit_completed_crcc,
        SUM(IF(dv.is_visit_unsuccessful AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_visit_unsuccessful_crcc,
        SUM(IF(dv.is_visit_stalled AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_visit_stalled_crcc,
        SUM(IF(dv.has_visit_finisher_status = False AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_visit_not_finished_crcc,
        SUM(IF(COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_offer_submitted_crcc,
        SUM(IF(COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_offer_accepted_crcc,
        SUM(IF(COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL AND heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_last_associated_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_agreement_signed_crcc
    FROM
        dw_visit.fact_visits AS fvs
    JOIN
        dw_visit.dim_visit AS dv
            ON fvs.sk_visit = dv.sk_visit
    JOIN
        dw_public.dim_user AS du
            ON fvs.sk_last_associated_agent = du.sk_user
    JOIN
        updated_base AS ub
            ON ub.uuid_person = du.uuid_person
            AND ub.date_ref = DATE(dv.dt_created)
    LEFT JOIN
        dw_house.dim_house_entrance_history AS heh
            ON fvs.sk_house_entrance = heh.sk_house_entrance
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit
            ON fvs.sk_visit = o_visit.id_visit_external
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit_fifty
            ON fvs.sk_visit = o_visit_fifty.id_visit_fifty_external
    GROUP BY 1,2
),
visit_funnel_metrics_vbba AS ( -- VBBA metrics for each agent + date (based on agent vbba)
    SELECT
        ub.uuid_person,
        ub.date_ref,
        SUM(IF(dv.is_vbba, 1, 0)) AS total_visit_vbba,
        SUM(IF(dv.is_vbba, fvs.nbr_reschedule, 0)) AS total_rescheduled_vbba,
        SUM(IF(dv.is_visit_canceled AND dv.is_vbba, 1, 0)) AS total_visit_canceled_vbba,
        SUM(IF(dv.is_visit_completed AND dv.is_vbba, 1, 0)) AS total_visit_completed_vbba,
        SUM(IF(dv.is_visit_unsuccessful AND dv.is_vbba, 1, 0)) AS total_visit_unsuccessful_vbba,
        SUM(IF(dv.is_visit_stalled AND dv.is_vbba, 1, 0)) AS total_visit_stalled_vbba,
        SUM(IF(dv.has_visit_finisher_status = False AND dv.is_vbba, 1, 0)) AS total_visit_not_finished_vbba,
        SUM(IF(COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL AND dv.is_vbba, 1, 0)) AS total_offer_submitted_vbba,
        SUM(IF(COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL AND dv.is_vbba, 1, 0)) AS total_offer_accepted_vbba,
        SUM(IF(COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL AND dv.is_vbba, 1, 0)) AS total_agreement_signed_vbba
    FROM
        dw_visit.fact_visits AS fvs
    JOIN
        dw_visit.dim_visit AS dv
            ON fvs.sk_visit = dv.sk_visit
    JOIN
        dw_public.dim_user AS du
            ON fvs.sk_user_agent_vbba = du.sk_user
    JOIN
        updated_base AS ub
            ON ub.uuid_person = du.uuid_person
            AND ub.date_ref = DATE(dv.dt_created)
    LEFT JOIN
        dw_house.dim_house_entrance_history AS heh
            ON fvs.sk_house_entrance = heh.sk_house_entrance
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit
            ON fvs.sk_visit = o_visit.id_visit_external
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit_fifty
            ON fvs.sk_visit = o_visit_fifty.id_visit_fifty_external
    GROUP BY 1,2
)
SELECT
    MD5(CONCAT(ub.uuid_person, ub.date_ref)) AS sk_agent_visit_funnel,
    ub.uuid_person,
    ub.date_ref,
    COALESCE(vfm.total_visit, 0) AS total_visit,
    COALESCE(vfm.total_rescheduled, 0) AS total_reschedule,
    COALESCE(vfm.total_visit_canceled, 0) AS total_visit_canceled,
    COALESCE(vfm.total_visit_completed, 0) AS total_visit_completed,
    COALESCE(vfm.total_visit_unsuccessful, 0) AS total_visit_unsuccessful,
    COALESCE(vfm.total_visit_stalled, 0) AS total_visit_stalled,
    COALESCE(vfm.total_visit_not_finished, 0) AS total_visit_not_finished,
    COALESCE(vfm.total_offer_submitted, 0) AS total_offer_submitted,
    COALESCE(vfm.total_offer_accepted, 0) AS total_offer_accepted,
    COALESCE(vfm.total_agreement_signed, 0) AS total_agreement_signed,
    COALESCE(vfm.total_visit_pfa, 0) AS total_visit_pfa,
    COALESCE(vfm.total_rescheduled_pfa, 0) AS total_reschedule_pfa,
    COALESCE(vfm.total_visit_canceled_pfa, 0) AS total_visit_canceled_pfa,
    COALESCE(vfm.total_visit_completed_pfa, 0) AS total_visit_completed_pfa,
    COALESCE(vfm.total_visit_unsuccessful_pfa, 0) AS total_visit_unsuccessful_pfa,
    COALESCE(vfm.total_visit_stalled_pfa, 0) AS total_visit_stalled_pfa,
    COALESCE(vfm.total_visit_not_finished_pfa, 0) AS total_visit_not_finished_pfa,
    COALESCE(vfm.total_offer_submitted_pfa, 0) AS total_offer_submitted_pfa,
    COALESCE(vfm.total_offer_accepted_pfa, 0) AS total_offer_accepted_pfa,
    COALESCE(vfm.total_agreement_signed_pfa, 0) AS total_agreement_signed_pfa,
    COALESCE(vfm.total_visit_crcc, 0) AS total_visit_crcc,
    COALESCE(vfm.total_rescheduled_crcc, 0) AS total_reschedule_crcc,
    COALESCE(vfm.total_visit_canceled_crcc, 0) AS total_visit_canceled_crcc,
    COALESCE(vfm.total_visit_completed_crcc, 0) AS total_visit_completed_crcc,
    COALESCE(vfm.total_visit_unsuccessful_crcc, 0) AS total_visit_unsuccessful_crcc,
    COALESCE(vfm.total_visit_stalled_crcc, 0) AS total_visit_stalled_crcc,
    COALESCE(vfm.total_visit_not_finished_crcc, 0) AS total_visit_not_finished_crcc,
    COALESCE(vfm.total_offer_submitted_crcc, 0) AS total_offer_submitted_crcc,
    COALESCE(vfm.total_offer_accepted_crcc, 0) AS total_offer_accepted_crcc,
    COALESCE(vfm.total_agreement_signed_crcc, 0) AS total_agreement_signed_crcc,
    COALESCE(vfm_vbba.total_visit_vbba, 0) AS total_visit_vbba,
    COALESCE(vfm_vbba.total_rescheduled_vbba, 0) AS total_reschedule_vbba,
    COALESCE(vfm_vbba.total_visit_canceled_vbba, 0) AS total_visit_canceled_vbba,
    COALESCE(vfm_vbba.total_visit_completed_vbba, 0) AS total_visit_completed_vbba,
    COALESCE(vfm_vbba.total_visit_unsuccessful_vbba, 0) AS total_visit_unsuccessful_vbba,
    COALESCE(vfm_vbba.total_visit_stalled_vbba, 0) AS total_visit_stalled_vbba,
    COALESCE(vfm_vbba.total_visit_not_finished_vbba, 0) AS total_visit_not_finished_vbba,
    COALESCE(vfm_vbba.total_offer_submitted_vbba, 0) AS total_offer_submitted_vbba,
    COALESCE(vfm_vbba.total_offer_accepted_vbba, 0) AS total_offer_accepted_vbba,
    COALESCE(vfm_vbba.total_agreement_signed_vbba, 0) AS total_agreement_signed_vbba,
    YEAR(ub.date_ref) AS year,
    MONTH(ub.date_ref) AS month,
    DAY(ub.date_ref) AS day
FROM
    updated_base AS ub
LEFT JOIN
    visit_funnel_metrics AS vfm
        ON ub.uuid_person = vfm.uuid_person
        AND ub.date_ref = vfm.date_ref
LEFT JOIN
    visit_funnel_metrics_vbba AS vfm_vbba
        ON ub.uuid_person = vfm_vbba.uuid_person
        AND ub.date_ref = vfm_vbba.date_ref
