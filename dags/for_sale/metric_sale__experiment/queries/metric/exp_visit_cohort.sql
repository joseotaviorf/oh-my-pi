WITH visit AS (
    SELECT
        fv.sk_visit,
        fv.sk_house,
        fv.sk_visitor,
        fv.sk_owner,
        fv.sk_first_associated_agent,
        dv.business_context,
        dv.dt_created,
        dv.ts_visit_done,
        dv.ts_visit_canceled,
        dv.ts_visit_unsuccessful,
        os.ts_first_event AS ts_offer_submitted,
        oa.ts_first_event AS ts_offer_accepted,
        cs.ts_first_event AS ts_contract_signed
    FROM
        dw_visit.fact_visits AS fv
    JOIN
        dw_visit.dim_visit AS dv
            ON fv.sk_visit = dv.sk_visit
    LEFT JOIN
        dw_visit.dim_visit_funnel AS os
            ON fv.sk_funnel_offer_submitted = os.sk_visit_funnel
    LEFT JOIN
        dw_visit.dim_visit_funnel AS oa
            ON fv.sk_funnel_offer_accepted = oa.sk_visit_funnel
    LEFT JOIN
        dw_visit.dim_visit_funnel AS cs
            ON fv.sk_funnel_contract_signed = cs.sk_visit_funnel
),
exp AS (
SELECT
    de.sk_neotribe_exp,
    fe.sk_identifier,
    de.name_neotribe,
    de.name_experiment,
    de.identifier_type,
    de.business_context,
    fe.test_group,
    de.dt_started,
    COALESCE(de.dt_ended, DATE(CURRENT_TIMESTAMP)) AS dt_ended
FROM
    dw_for_sale_experiment.fact_experiment AS fe
JOIN
    dw_for_sale_experiment.dim_experiment AS de
        ON fe.sk_neotribe_exp = de.sk_neotribe_exp
),
visit_exp AS (
  WITH visit_by_visitor AS (
    SELECT
        exp.sk_neotribe_exp,
        visit.sk_visit,
        visit.sk_house,
        visit.sk_visitor,
        visit.sk_owner,
        visit.sk_first_associated_agent,
        visit.business_context,
        exp.name_neotribe AS exp_name_neotribe,
        exp.name_experiment AS exp_name_experiment,
        exp.identifier_type AS exp_identifier_type,
        exp.test_group AS exp_test_group,
        visit.dt_created,
        visit.ts_visit_done,
        visit.ts_visit_canceled,
        visit.ts_visit_unsuccessful,
        visit.ts_offer_submitted,
        visit.ts_offer_accepted,
        visit.ts_contract_signed,
        exp.dt_started AS dt_exp_started,
        exp.dt_ended AS dt_exp_ended
    FROM
      visit
    JOIN
      exp
        ON exp.identifier_type = 'VISITOR'
        AND visit.sk_visitor = exp.sk_identifier
        AND visit.business_context = exp.business_context
        AND visit.dt_created::DATE >= exp.dt_started
        AND visit.dt_created::DATE <= exp.dt_ended
    )
    SELECT
        sk_neotribe_exp,
        sk_visit,
        sk_house,
        sk_visitor,
        sk_owner,
        sk_first_associated_agent,
        business_context,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        exp_test_group,
        dt_created,
        ts_visit_done,
        ts_visit_canceled,
        ts_visit_unsuccessful,
        ts_offer_submitted,
        ts_offer_accepted,
        ts_contract_signed,
        dt_exp_started,
        dt_exp_ended
    FROM
        visit_by_visitor
),
exp_cohort_1d AS (
    SELECT
        visit_exp.sk_neotribe_exp,
        visit_exp.sk_visit,
        visit_exp.sk_house,
        visit_exp.sk_visitor,
        visit_exp.sk_owner,
        visit_exp.sk_first_associated_agent,
        visit_exp.business_context,
        visit_exp.exp_name_neotribe,
        visit_exp.exp_name_experiment,
        visit_exp.exp_identifier_type,
        visit_exp.exp_test_group,
        '1d' AS metric_cohort,
        DATEDIFF(dim_date.date, visit_exp.dt_created) AS days_since_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_created) AS days_to_vc,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_created) AS days_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_created) AS days_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_created) AS days_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_created) AS days_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_created) AS days_to_cs,
        IF(days_since_vb > 1, 1, 0) AS num_vb,
        IF(days_since_vb > 1 AND days_to_vc <= 1, 1, 0) AS num_vc,
        IF(days_since_vb > 1 AND days_to_vcc <= 1, 1, 0) AS num_vcc,
        IF(days_since_vb > 1 AND days_to_vu <= 1, 1, 0) AS num_vu,
        IF(days_since_vb > 1 AND days_to_os <= 1, 1, 0) AS num_os,
        IF(days_since_vb > 1 AND days_to_oa <= 1, 1, 0) AS num_oa,
        IF(days_since_vb > 1 AND days_to_cs <= 1, 1, 0) AS num_cs,
        visit_exp.dt_exp_started,
        visit_exp.dt_exp_ended,
        dim_date.date AS dt_ref
    FROM
        visit_exp
    JOIN
        dw_public.dim_date
            ON dim_date.date >= visit_exp.dt_created::DATE
            AND dim_date.date <= visit_exp.dt_exp_ended
),
exp_cohort_3d AS (
    SELECT
        visit_exp.sk_neotribe_exp,
        visit_exp.sk_visit,
        visit_exp.sk_house,
        visit_exp.sk_visitor,
        visit_exp.sk_owner,
        visit_exp.sk_first_associated_agent,
        visit_exp.business_context,
        visit_exp.exp_name_neotribe,
        visit_exp.exp_name_experiment,
        visit_exp.exp_identifier_type,
        visit_exp.exp_test_group,
        '3d' AS metric_cohort,
        DATEDIFF(dim_date.date, visit_exp.dt_created) AS days_since_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_created) AS days_to_vc,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_created) AS days_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_created) AS days_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_created) AS days_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_created) AS days_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_created) AS days_to_cs,
        IF(days_since_vb > 3, 1, 0) AS num_vb,
        IF(days_since_vb > 3 AND days_to_vc <= 3, 1, 0) AS num_vc,
        IF(days_since_vb > 3 AND days_to_vcc <= 3, 1, 0) AS num_vcc,
        IF(days_since_vb > 3 AND days_to_vu <= 3, 1, 0) AS num_vu,
        IF(days_since_vb > 3 AND days_to_os <= 3, 1, 0) AS num_os,
        IF(days_since_vb > 3 AND days_to_oa <= 3, 1, 0) AS num_oa,
        IF(days_since_vb > 3 AND days_to_cs <= 3, 1, 0) AS num_cs,
        visit_exp.dt_exp_started,
        visit_exp.dt_exp_ended,
        dim_date.date AS dt_ref
    FROM
        visit_exp
    JOIN
        dw_public.dim_date
            ON dim_date.date >= visit_exp.dt_created::DATE
            AND dim_date.date <= visit_exp.dt_exp_ended
),
exp_cohort_7d AS (
    SELECT
        visit_exp.sk_neotribe_exp,
        visit_exp.sk_visit,
        visit_exp.sk_house,
        visit_exp.sk_visitor,
        visit_exp.sk_owner,
        visit_exp.sk_first_associated_agent,
        visit_exp.business_context,
        visit_exp.exp_name_neotribe,
        visit_exp.exp_name_experiment,
        visit_exp.exp_identifier_type,
        visit_exp.exp_test_group,
        '7d' AS metric_cohort,
        DATEDIFF(dim_date.date, visit_exp.dt_created) AS days_since_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_created) AS days_to_vc,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_created) AS days_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_created) AS days_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_created) AS days_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_created) AS days_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_created) AS days_to_cs,
        IF(days_since_vb > 7, 1, 0) AS num_vb,
        IF(days_since_vb > 7 AND days_to_vc <= 7, 1, 0) AS num_vc,
        IF(days_since_vb > 7 AND days_to_vcc <= 7, 1, 0) AS num_vcc,
        IF(days_since_vb > 7 AND days_to_vu <= 7, 1, 0) AS num_vu,
        IF(days_since_vb > 7 AND days_to_os <= 7, 1, 0) AS num_os,
        IF(days_since_vb > 7 AND days_to_oa <= 7, 1, 0) AS num_oa,
        IF(days_since_vb > 7 AND days_to_cs <= 7, 1, 0) AS num_cs,
        visit_exp.dt_exp_started,
        visit_exp.dt_exp_ended,
        dim_date.date AS dt_ref
    FROM
        visit_exp
    JOIN
        dw_public.dim_date
            ON dim_date.date >= visit_exp.dt_created::DATE
            AND dim_date.date <= visit_exp.dt_exp_ended
),
exp_cohort_14d AS (
    SELECT
        visit_exp.sk_neotribe_exp,
        visit_exp.sk_visit,
        visit_exp.sk_house,
        visit_exp.sk_visitor,
        visit_exp.sk_owner,
        visit_exp.sk_first_associated_agent,
        visit_exp.business_context,
        visit_exp.exp_name_neotribe,
        visit_exp.exp_name_experiment,
        visit_exp.exp_identifier_type,
        visit_exp.exp_test_group,
        '14d' AS metric_cohort,
        DATEDIFF(dim_date.date, visit_exp.dt_created) AS days_since_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_created) AS days_to_vc,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_created) AS days_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_created) AS days_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_created) AS days_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_created) AS days_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_created) AS days_to_cs,
        IF(days_since_vb > 14, 1, 0) AS num_vb,
        IF(days_since_vb > 14 AND days_to_vc <= 14, 1, 0) AS num_vc,
        IF(days_since_vb > 14 AND days_to_vcc <= 14, 1, 0) AS num_vcc,
        IF(days_since_vb > 14 AND days_to_vu <= 14, 1, 0) AS num_vu,
        IF(days_since_vb > 14 AND days_to_os <= 14, 1, 0) AS num_os,
        IF(days_since_vb > 14 AND days_to_oa <= 14, 1, 0) AS num_oa,
        IF(days_since_vb > 14 AND days_to_cs <= 14, 1, 0) AS num_cs,
        visit_exp.dt_exp_started,
        visit_exp.dt_exp_ended,
        dim_date.date AS dt_ref
    FROM
        visit_exp
    JOIN
        dw_public.dim_date
            ON dim_date.date >= visit_exp.dt_created::DATE
            AND dim_date.date <= visit_exp.dt_exp_ended
),
exp_cohort_21d AS (
    SELECT
        visit_exp.sk_neotribe_exp,
        visit_exp.sk_visit,
        visit_exp.sk_house,
        visit_exp.sk_visitor,
        visit_exp.sk_owner,
        visit_exp.sk_first_associated_agent,
        visit_exp.business_context,
        visit_exp.exp_name_neotribe,
        visit_exp.exp_name_experiment,
        visit_exp.exp_identifier_type,
        visit_exp.exp_test_group,
        '21d' AS metric_cohort,
        DATEDIFF(dim_date.date, visit_exp.dt_created) AS days_since_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_created) AS days_to_vc,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_created) AS days_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_created) AS days_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_created) AS days_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_created) AS days_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_created) AS days_to_cs,
        IF(days_since_vb > 21, 1, 0) AS num_vb,
        IF(days_since_vb > 21 AND days_to_vc <= 21, 1, 0) AS num_vc,
        IF(days_since_vb > 21 AND days_to_vcc <= 21, 1, 0) AS num_vcc,
        IF(days_since_vb > 21 AND days_to_vu <= 21, 1, 0) AS num_vu,
        IF(days_since_vb > 21 AND days_to_os <= 21, 1, 0) AS num_os,
        IF(days_since_vb > 21 AND days_to_oa <= 21, 1, 0) AS num_oa,
        IF(days_since_vb > 21 AND days_to_cs <= 21, 1, 0) AS num_cs,
        visit_exp.dt_exp_started,
        visit_exp.dt_exp_ended,
        dim_date.date AS dt_ref
    FROM
        visit_exp
    JOIN
        dw_public.dim_date
            ON dim_date.date >= visit_exp.dt_created::DATE
            AND dim_date.date <= visit_exp.dt_exp_ended
),
exp_cohort_28d AS (
    SELECT
        visit_exp.sk_neotribe_exp,
        visit_exp.sk_visit,
        visit_exp.sk_house,
        visit_exp.sk_visitor,
        visit_exp.sk_owner,
        visit_exp.sk_first_associated_agent,
        visit_exp.business_context,
        visit_exp.exp_name_neotribe,
        visit_exp.exp_name_experiment,
        visit_exp.exp_identifier_type,
        visit_exp.exp_test_group,
        '28d' AS metric_cohort,
        DATEDIFF(dim_date.date, visit_exp.dt_created) AS days_since_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_created) AS days_to_vc,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_created) AS days_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_created) AS days_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_created) AS days_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_created) AS days_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_created) AS days_to_cs,
        IF(days_since_vb > 28, 1, 0) AS num_vb,
        IF(days_since_vb > 28 AND days_to_vc <= 28, 1, 0) AS num_vc,
        IF(days_since_vb > 28 AND days_to_vcc <= 28, 1, 0) AS num_vcc,
        IF(days_since_vb > 28 AND days_to_vu <= 28, 1, 0) AS num_vu,
        IF(days_since_vb > 28 AND days_to_os <= 28, 1, 0) AS num_os,
        IF(days_since_vb > 28 AND days_to_oa <= 28, 1, 0) AS num_oa,
        IF(days_since_vb > 28 AND days_to_cs <= 28, 1, 0) AS num_cs,
        visit_exp.dt_exp_started,
        visit_exp.dt_exp_ended,
        dim_date.date AS dt_ref
    FROM
        visit_exp
    JOIN
        dw_public.dim_date
            ON dim_date.date >= visit_exp.dt_created::DATE
            AND dim_date.date <= visit_exp.dt_exp_ended
)
SELECT
    MD5(sk_neotribe_exp || sk_visit || metric_cohort || dt_ref) AS sk_exp_visit_cohort,
    sk_neotribe_exp,
    sk_visit,
    sk_house,
    sk_visitor,
    sk_owner,
    sk_first_associated_agent,
    business_context,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    exp_test_group,
    metric_cohort,
    num_vb,
    num_vc,
    num_vcc,
    num_vu,
    num_os,
    num_oa,
    num_cs,
    dt_exp_started,
    dt_exp_ended,
    dt_ref
FROM
    exp_cohort_1d
UNION ALL
SELECT
    MD5(sk_neotribe_exp || sk_visit || metric_cohort || dt_ref) AS sk_exp_visit_cohort,
    sk_neotribe_exp,
    sk_visit,
    sk_house,
    sk_visitor,
    sk_owner,
    sk_first_associated_agent,
    business_context,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    exp_test_group,
    metric_cohort,
    num_vb,
    num_vc,
    num_vcc,
    num_vu,
    num_os,
    num_oa,
    num_cs,
    dt_exp_started,
    dt_exp_ended,
    dt_ref
FROM
    exp_cohort_3d
UNION ALL
SELECT
    MD5(sk_neotribe_exp || sk_visit || metric_cohort || dt_ref) AS sk_exp_visit_cohort,
    sk_neotribe_exp,
    sk_visit,
    sk_house,
    sk_visitor,
    sk_owner,
    sk_first_associated_agent,
    business_context,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    exp_test_group,
    metric_cohort,
    num_vb,
    num_vc,
    num_vcc,
    num_vu,
    num_os,
    num_oa,
    num_cs,
    dt_exp_started,
    dt_exp_ended,
    dt_ref
FROM
    exp_cohort_7d
UNION ALL
SELECT
    MD5(sk_neotribe_exp || sk_visit || metric_cohort || dt_ref) AS sk_exp_visit_cohort,
    sk_neotribe_exp,
    sk_visit,
    sk_house,
    sk_visitor,
    sk_owner,
    sk_first_associated_agent,
    business_context,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    exp_test_group,
    metric_cohort,
    num_vb,
    num_vc,
    num_vcc,
    num_vu,
    num_os,
    num_oa,
    num_cs,
    dt_exp_started,
    dt_exp_ended,
    dt_ref
FROM
    exp_cohort_14d
UNION ALL
SELECT
    MD5(sk_neotribe_exp || sk_visit || metric_cohort || dt_ref) AS sk_exp_visit_cohort,
    sk_neotribe_exp,
    sk_visit,
    sk_house,
    sk_visitor,
    sk_owner,
    sk_first_associated_agent,
    business_context,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    exp_test_group,
    metric_cohort,
    num_vb,
    num_vc,
    num_vcc,
    num_vu,
    num_os,
    num_oa,
    num_cs,
    dt_exp_started,
    dt_exp_ended,
    dt_ref
FROM
    exp_cohort_21d
UNION ALL
SELECT
    MD5(sk_neotribe_exp || sk_visit || metric_cohort || dt_ref) AS sk_exp_visit_cohort,
    sk_neotribe_exp,
    sk_visit,
    sk_house,
    sk_visitor,
    sk_owner,
    sk_first_associated_agent,
    business_context,
    exp_name_neotribe,
    exp_name_experiment,
    exp_identifier_type,
    exp_test_group,
    metric_cohort,
    num_vb,
    num_vc,
    num_vcc,
    num_vu,
    num_os,
    num_oa,
    num_cs,
    dt_exp_started,
    dt_exp_ended,
    dt_ref
FROM
    exp_cohort_28d
