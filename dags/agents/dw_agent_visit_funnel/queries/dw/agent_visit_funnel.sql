WITH schedule_update AS (
    SELECT DISTINCT
        du.uuid_person,
        DATE(dvs.ts_schedule_created) AS date_ref
    FROM
        dw_visit.fact_visit_schedules AS fvs
    JOIN
        dw_visit.dim_visit_schedule AS dvs
        ON fvs.sk_schedule = dvs.sk_schedule
    JOIN
        dw_visit.dim_visit AS dv
            ON fvs.sk_visit = dv.sk_visit
    JOIN
        dw_public.dim_user AS du
            ON fvs.sk_user_agent = du.sk_user
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit
            ON fvs.sk_visit = o_visit.id_visit_external
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit_fifty
            ON fvs.sk_schedule = o_visit_fifty.id_visit_fifty_external
    WHERE
        GREATEST(
            DATE(dvs.ts_schedule_created),
            DATE(dvs.ts_next_schedule_created),
            DATE(dv.ts_visit_done),
            DATE(dv.ts_visit_unsuccessful),
            DATE(dv.ts_visit_stalled),
            DATE(dv.ts_visit_canceled),
            DATE(o_visit.ts_updated),
            DATE(o_visit_fifty.ts_updated)
        ) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
allow_demand_visit_base AS (
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
    SELECT
        uuid_person,
        date_ref
    FROM
        schedule_update
    UNION
    SELECT
        uuid_person,
        date_ref
    FROM
        allow_demand_visit_base
),
schedule_enriched AS (
    SELECT
        vu.uuid_person,
        vu.date_ref,
        SUM(fvs.is_booking) AS total_schedule,
        SUM(IF(dvs.ts_next_schedule_created IS NOT NULL, 1, 0)) AS total_rescheduled,
        SUM(IF(dvs.ts_next_schedule_created IS NULL, fv.num_visit_canceled, 0)) AS total_visit_canceled,
        SUM(IF(dvs.ts_next_schedule_created IS NULL, fv.num_visit_completed, 0)) AS total_visit_completed,
        SUM(IF(dvs.ts_next_schedule_created IS NULL, fv.num_visit_unsuccessful, 0)) AS total_visit_unsuccessful,
        SUM(IF(dvs.ts_next_schedule_created IS NULL AND dv.ts_visit_stalled IS NOT NULL, 1, 0)) AS total_visit_stalled,
        SUM(IF(has_visit_finisher_status OR dvs.ts_next_schedule_created IS NOT NULL, 0, 1)) AS total_schedule_not_finished,
        SUM(IF(COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_submitted,
        SUM(IF(COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_accepted,
        SUM(IF(COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_agreement_signed,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent, 1, 0)) AS total_schedule_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND dvs.ts_next_schedule_created IS NOT NULL, 1, 0)) AS total_rescheduled_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_canceled, 0)) AS total_visit_canceled_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_completed, 0)) AS total_visit_completed_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_unsuccessful, 0)) AS total_visit_unsuccessful_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND dvs.ts_next_schedule_created IS NULL AND dv.ts_visit_stalled IS NOT NULL, 1, 0)) AS total_visit_stalled_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND has_visit_finisher_status = False AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_schedule_not_finished_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_submitted_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_accepted_pfa,
        SUM(IF(fvs.sk_user_agent = fvs.sk_user_fixed_agent AND COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_agreement_signed_pfa,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED', 1, 0)) AS total_schedule_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND dvs.ts_next_schedule_created IS NOT NULL, 1, 0)) AS total_rescheduled_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_canceled, 0)) AS total_visit_canceled_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_completed, 0)) AS total_visit_completed_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_unsuccessful, 0)) AS total_visit_unsuccessful_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND dvs.ts_next_schedule_created IS NULL AND dv.ts_visit_stalled IS NOT NULL, 1, 0)) AS total_visit_stalled_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND has_visit_finisher_status = False AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_schedule_not_finished_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_submitted_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_accepted_crcc,
        SUM(IF(heh.key_location = 'AGENT' AND heh.sk_user_key_holder = fvs.sk_user_agent AND heh.event_type <> 'KEY_HOLDER_DEALLOCATED' AND COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_agreement_signed_crcc,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN), 1, 0)) AS total_schedule_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND dvs.ts_next_schedule_created IS NOT NULL, 1, 0)) AS total_rescheduled_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_canceled, 0)) AS total_visit_canceled_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_completed, 0)) AS total_visit_completed_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND dvs.ts_next_schedule_created IS NULL, fv.num_visit_unsuccessful, 0)) AS total_visit_unsuccessful_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND dvs.ts_next_schedule_created IS NULL AND dv.ts_visit_stalled IS NOT NULL, 1, 0)) AS total_visit_stalled_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND has_visit_finisher_status = False AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_schedule_not_finished_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND COALESCE(o_visit.ts_offer_submitted, o_visit_fifty.ts_offer_submitted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_submitted_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND COALESCE(o_visit.ts_offer_accepted, o_visit_fifty.ts_offer_accepted) IS NOT NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_offer_accepted_vbba,
        SUM(IF(CAST(is_schedule_vbba AS BOOLEAN) AND COALESCE(o_visit.ts_sale_agreement_signed, o_visit_fifty.ts_sale_agreement_signed) IS NOT NULL AND COALESCE(o_visit.ts_sale_agreement_canceled, o_visit_fifty.ts_sale_agreement_canceled) IS NULL AND dvs.ts_next_schedule_created IS NULL, 1, 0)) AS total_agreement_signed_vbba
    FROM
        dw_visit.fact_visit_schedules AS fvs
    JOIN
        dw_visit.dim_visit_schedule AS dvs
            ON fvs.sk_schedule = dvs.sk_schedule
    JOIN
        dw_visit.fact_visits AS fv
            ON fvs.sk_visit = fv.sk_visit
    JOIN
        dw_visit.dim_visit AS dv
            ON fvs.sk_visit = dv.sk_visit
    JOIN
        dw_public.dim_user AS du
            ON fvs.sk_user_agent = du.sk_user
    JOIN
        schedule_update AS vu
            ON vu.uuid_person = du.uuid_person
            AND vu.date_ref = DATE(dvs.ts_schedule_created)
    LEFT JOIN
        dw_house.dim_house_entrance_history AS heh
            ON fvs.sk_house_entrance_visit = heh.sk_house_entrance
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit
            ON fvs.sk_visit = o_visit.id_visit_external
    LEFT JOIN
        datalake_sale_offer.sale_offer AS o_visit_fifty
            ON fvs.sk_schedule = o_visit_fifty.id_visit_fifty_external
    GROUP BY 1,2
)
SELECT
    MD5(CONCAT(ub.uuid_person, ub.date_ref)) AS sk_agent_visit_funnel,
    ub.uuid_person,
    ub.date_ref,
    COALESCE(se.total_schedule, 0) AS total_schedule,
    COALESCE(se.total_rescheduled, 0) AS total_reschedule,
    COALESCE(se.total_visit_canceled, 0) AS total_visit_canceled,
    COALESCE(se.total_visit_completed, 0) AS total_visit_completed,
    COALESCE(se.total_visit_unsuccessful, 0) AS total_visit_unsuccessful,
    COALESCE(se.total_visit_stalled, 0) AS total_visit_stalled,
    COALESCE(se.total_schedule_not_finished, 0) AS total_schedule_not_finished,
    COALESCE(se.total_offer_submitted, 0) AS total_offer_submitted,
    COALESCE(se.total_offer_accepted, 0) AS total_offer_accepted,
    COALESCE(se.total_agreement_signed, 0) AS total_agreement_signed,
    COALESCE(se.total_schedule_pfa, 0) AS total_schedule_pfa,
    COALESCE(se.total_rescheduled_pfa, 0) AS total_reschedule_pfa,
    COALESCE(se.total_visit_canceled_pfa, 0) AS total_visit_canceled_pfa,
    COALESCE(se.total_visit_completed_pfa, 0) AS total_visit_completed_pfa,
    COALESCE(se.total_visit_unsuccessful_pfa, 0) AS total_visit_unsuccessful_pfa,
    COALESCE(se.total_visit_stalled_pfa, 0) AS total_visit_stalled_pfa,
    COALESCE(se.total_schedule_not_finished_pfa, 0) AS total_schedule_not_finished_pfa,
    COALESCE(se.total_offer_submitted_pfa, 0) AS total_offer_submitted_pfa,
    COALESCE(se.total_offer_accepted_pfa, 0) AS total_offer_accepted_pfa,
    COALESCE(se.total_agreement_signed_pfa, 0) AS total_agreement_signed_pfa,
    COALESCE(se.total_schedule_crcc, 0) AS total_schedule_crcc,
    COALESCE(se.total_rescheduled_crcc, 0) AS total_reschedule_crcc,
    COALESCE(se.total_visit_canceled_crcc, 0) AS total_visit_canceled_crcc,
    COALESCE(se.total_visit_completed_crcc, 0) AS total_visit_completed_crcc,
    COALESCE(se.total_visit_unsuccessful_crcc, 0) AS total_visit_unsuccessful_crcc,
    COALESCE(se.total_visit_stalled_crcc, 0) AS total_visit_stalled_crcc,
    COALESCE(se.total_schedule_not_finished_crcc, 0) AS total_schedule_not_finished_crcc,
    COALESCE(se.total_offer_submitted_crcc, 0) AS total_offer_submitted_crcc,
    COALESCE(se.total_offer_accepted_crcc, 0) AS total_offer_accepted_crcc,
    COALESCE(se.total_agreement_signed_crcc, 0) AS total_agreement_signed_crcc,
    COALESCE(se.total_schedule_vbba, 0) AS total_schedule_vbba,
    COALESCE(se.total_rescheduled_vbba, 0) AS total_reschedule_vbba,
    COALESCE(se.total_visit_canceled_vbba, 0) AS total_visit_canceled_vbba,
    COALESCE(se.total_visit_completed_vbba, 0) AS total_visit_completed_vbba,
    COALESCE(se.total_visit_unsuccessful_vbba, 0) AS total_visit_unsuccessful_vbba,
    COALESCE(se.total_visit_stalled_vbba, 0) AS total_visit_stalled_vbba,
    COALESCE(se.total_schedule_not_finished_vbba, 0) AS total_schedule_not_finished_vbba,
    COALESCE(se.total_offer_submitted_vbba, 0) AS total_offer_submitted_vbba,
    COALESCE(se.total_offer_accepted_vbba, 0) AS total_offer_accepted_vbba,
    COALESCE(se.total_agreement_signed_vbba, 0) AS total_agreement_signed_vbba,
    YEAR(ub.date_ref) AS year,
    MONTH(ub.date_ref) AS month,
    DAY(ub.date_ref) AS day
FROM
    updated_base AS ub
LEFT JOIN
    schedule_enriched AS se
        ON ub.uuid_person = se.uuid_person
        AND ub.date_ref = se.date_ref
