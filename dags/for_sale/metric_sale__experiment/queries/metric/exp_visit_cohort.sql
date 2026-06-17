WITH visit AS (
    SELECT
        fv.sk_visit,
        fv.sk_house,
        fv.sk_visitor,
        fv.sk_owner,
        fv.sk_first_associated_agent,
        dv.business_context,
        dv.behavior,
        dv.dt_created,
        dv.ts_visit_first_confirmed,
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
        de.sk_experiment,
        de.name_neotribe,
        de.name_experiment,
        de.identifier_type,
        de.business_context,
        fe.test_group,
        fe.dt_identifier_started,
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
            exp.sk_identifier AS sk_exp_identifier,
            visit.business_context,
            exp.name_neotribe AS exp_name_neotribe,
            CONCAT(exp.sk_experiment,' | ',exp.name_experiment) AS exp_name_experiment,
            exp.identifier_type AS exp_identifier_type,
            exp.test_group AS exp_test_group,
            visit.dt_created,
            visit.ts_visit_first_confirmed,
            visit.ts_visit_done,
            visit.ts_visit_canceled,
            visit.ts_visit_unsuccessful,
            visit.ts_offer_submitted,
            visit.ts_offer_accepted,
            visit.ts_contract_signed,
            exp.dt_identifier_started,
            exp.dt_started AS dt_exp_started,
            exp.dt_ended AS dt_exp_ended
        FROM
            visit
        JOIN
            exp
                ON exp.identifier_type = 'VISITOR'
                AND visit.sk_visitor = exp.sk_identifier
                AND visit.business_context = exp.business_context
                AND DATE(visit.dt_created) >= exp.dt_started
                AND DATE(visit.dt_created) <= exp.dt_ended
    ),
    visit_by_visit AS (
        SELECT
            exp.sk_neotribe_exp,
            visit.sk_visit,
            visit.sk_house,
            visit.sk_visitor,
            visit.sk_owner,
            visit.sk_first_associated_agent,
            exp.sk_identifier AS sk_exp_identifier,
            visit.business_context,
            exp.name_neotribe AS exp_name_neotribe,
            CONCAT(exp.sk_experiment,' | ',exp.name_experiment) AS exp_name_experiment,
            exp.identifier_type AS exp_identifier_type,
            exp.test_group AS exp_test_group,
            visit.dt_created,
            visit.ts_visit_first_confirmed,
            visit.ts_visit_done,
            visit.ts_visit_canceled,
            visit.ts_visit_unsuccessful,
            visit.ts_offer_submitted,
            visit.ts_offer_accepted,
            visit.ts_contract_signed,
            exp.dt_identifier_started,
            exp.dt_started AS dt_exp_started,
            exp.dt_ended AS dt_exp_ended
        FROM
            visit
        JOIN
            exp
                ON exp.identifier_type = 'VISIT'
                AND visit.sk_visit = exp.sk_identifier
                AND visit.business_context = exp.business_context
                AND DATE(visit.dt_created) >= exp.dt_started
                AND DATE(visit.dt_created) <= exp.dt_ended
    ),
    visit_by_owner AS (
        SELECT
            exp.sk_neotribe_exp,
            visit.sk_visit,
            visit.sk_house,
            visit.sk_visitor,
            visit.sk_owner,
            visit.sk_first_associated_agent,
            exp.sk_identifier AS sk_exp_identifier,
            visit.business_context,
            exp.name_neotribe AS exp_name_neotribe,
            CONCAT(exp.sk_experiment,' | ',exp.name_experiment) AS exp_name_experiment,
            exp.identifier_type AS exp_identifier_type,
            exp.test_group AS exp_test_group,
            visit.dt_created,
            visit.ts_visit_first_confirmed,
            visit.ts_visit_done,
            visit.ts_visit_canceled,
            visit.ts_visit_unsuccessful,
            visit.ts_offer_submitted,
            visit.ts_offer_accepted,
            visit.ts_contract_signed,
            exp.dt_identifier_started,
            exp.dt_started AS dt_exp_started,
            exp.dt_ended AS dt_exp_ended
        FROM
            visit
        JOIN
            exp
                ON exp.identifier_type = 'OWNER'
                AND visit.sk_owner = exp.sk_identifier
                AND visit.business_context = exp.business_context
                AND DATE(visit.dt_created) >= exp.dt_started
                AND DATE(visit.dt_created) <= exp.dt_ended
        WHERE
            exp.name_experiment != 'visits_triangulation_owner'
            OR (
                exp.name_experiment = 'visits_triangulation_owner'
                AND visit.behavior IN ('INSTANT_BOOKING', 'CONFIRMATION_SUPPLY')
            )
    )
    SELECT
        sk_neotribe_exp,
        sk_visit,
        sk_house,
        sk_visitor,
        sk_owner,
        sk_first_associated_agent,
        sk_exp_identifier,
        business_context,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        exp_test_group,
        dt_created,
        ts_visit_first_confirmed,
        ts_visit_done,
        ts_visit_canceled,
        ts_visit_unsuccessful,
        ts_offer_submitted,
        ts_offer_accepted,
        ts_contract_signed,
        dt_identifier_started,
        dt_exp_started,
        dt_exp_ended
    FROM
        visit_by_visitor
    UNION ALL
    SELECT
        sk_neotribe_exp,
        sk_visit,
        sk_house,
        sk_visitor,
        sk_owner,
        sk_first_associated_agent,
        sk_exp_identifier,
        business_context,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        exp_test_group,
        dt_created,
        ts_visit_first_confirmed,
        ts_visit_done,
        ts_visit_canceled,
        ts_visit_unsuccessful,
        ts_offer_submitted,
        ts_offer_accepted,
        ts_contract_signed,
        dt_identifier_started,
        dt_exp_started,
        dt_exp_ended
    FROM
        visit_by_visit
    UNION ALL
    SELECT
        sk_neotribe_exp,
        sk_visit,
        sk_house,
        sk_visitor,
        sk_owner,
        sk_first_associated_agent,
        sk_exp_identifier,
        business_context,
        exp_name_neotribe,
        exp_name_experiment,
        exp_identifier_type,
        exp_test_group,
        dt_created,
        ts_visit_first_confirmed,
        ts_visit_done,
        ts_visit_canceled,
        ts_visit_unsuccessful,
        ts_offer_submitted,
        ts_offer_accepted,
        ts_contract_signed,
        dt_identifier_started,
        dt_exp_started,
        dt_exp_ended
    FROM
        visit_by_owner
),
exp_cohort AS (
    SELECT
        visit_exp.sk_neotribe_exp,
        visit_exp.sk_visit,
        visit_exp.sk_house,
        visit_exp.sk_visitor,
        visit_exp.sk_owner,
        visit_exp.sk_first_associated_agent,
        visit_exp.sk_exp_identifier,
        visit_exp.business_context,
        visit_exp.exp_name_neotribe,
        visit_exp.exp_name_experiment,
        visit_exp.exp_identifier_type,
        visit_exp.exp_test_group,
        -- visit conversion
        DATEDIFF(dim_date.date, visit_exp.dt_created) AS days_since_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_created) AS days_from_vb_to_vc,
        DATEDIFF(visit_exp.ts_visit_first_confirmed, visit_exp.dt_created) AS days_from_vb_to_vcf,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_created) AS days_from_vb_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_created) AS days_from_vb_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_created) AS days_from_vb_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_created) AS days_from_vb_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_created) AS days_from_vb_to_cs,
        IF(days_since_vb > 1, 1, 0) AS num_vb_1d,
        IF(days_since_vb > 1 AND days_from_vb_to_vc <= 1, 1, 0) AS num_vc_1d,
        IF(days_since_vb > 1 AND days_from_vb_to_vcf <= 1, 1, 0) AS num_vcf_1d,
        IF(days_since_vb > 1 AND days_from_vb_to_vcc <= 1, 1, 0) AS num_vcc_1d,
        IF(days_since_vb > 1 AND days_from_vb_to_vu <= 1, 1, 0) AS num_vu_1d,
        IF(days_since_vb > 1 AND days_from_vb_to_os <= 1, 1, 0) AS num_os_1d,
        IF(days_since_vb > 1 AND days_from_vb_to_oa <= 1, 1, 0) AS num_oa_1d,
        IF(days_since_vb > 1 AND days_from_vb_to_cs <= 1, 1, 0) AS num_cs_1d,
        IF(days_since_vb > 3, 1, 0) AS num_vb_3d,
        IF(days_since_vb > 3 AND days_from_vb_to_vc <= 3, 1, 0) AS num_vc_3d,
        IF(days_since_vb > 3 AND days_from_vb_to_vcf <= 3, 1, 0) AS num_vcf_3d,
        IF(days_since_vb > 3 AND days_from_vb_to_vcc <= 3, 1, 0) AS num_vcc_3d,
        IF(days_since_vb > 3 AND days_from_vb_to_vu <= 3, 1, 0) AS num_vu_3d,
        IF(days_since_vb > 3 AND days_from_vb_to_os <= 3, 1, 0) AS num_os_3d,
        IF(days_since_vb > 3 AND days_from_vb_to_oa <= 3, 1, 0) AS num_oa_3d,
        IF(days_since_vb > 3 AND days_from_vb_to_cs <= 3, 1, 0) AS num_cs_3d,
        IF(days_since_vb > 7, 1, 0) AS num_vb_7d,
        IF(days_since_vb > 7 AND days_from_vb_to_vc <= 7, 1, 0) AS num_vc_7d,
        IF(days_since_vb > 7 AND days_from_vb_to_vcf <= 7, 1, 0) AS num_vcf_7d,
        IF(days_since_vb > 7 AND days_from_vb_to_vcc <= 7, 1, 0) AS num_vcc_7d,
        IF(days_since_vb > 7 AND days_from_vb_to_vu <= 7, 1, 0) AS num_vu_7d,
        IF(days_since_vb > 7 AND days_from_vb_to_os <= 7, 1, 0) AS num_os_7d,
        IF(days_since_vb > 7 AND days_from_vb_to_oa <= 7, 1, 0) AS num_oa_7d,
        IF(days_since_vb > 7 AND days_from_vb_to_cs <= 7, 1, 0) AS num_cs_7d,
        IF(days_since_vb > 14, 1, 0) AS num_vb_14d,
        IF(days_since_vb > 14 AND days_from_vb_to_vc <= 14, 1, 0) AS num_vc_14d,
        IF(days_since_vb > 14 AND days_from_vb_to_vcf <= 14, 1, 0) AS num_vcf_14d,
        IF(days_since_vb > 14 AND days_from_vb_to_vcc <= 14, 1, 0) AS num_vcc_14d,
        IF(days_since_vb > 14 AND days_from_vb_to_vu <= 14, 1, 0) AS num_vu_14d,
        IF(days_since_vb > 14 AND days_from_vb_to_os <= 14, 1, 0) AS num_os_14d,
        IF(days_since_vb > 14 AND days_from_vb_to_oa <= 14, 1, 0) AS num_oa_14d,
        IF(days_since_vb > 14 AND days_from_vb_to_cs <= 14, 1, 0) AS num_cs_14d,
        IF(days_since_vb > 21, 1, 0) AS num_vb_21d,
        IF(days_since_vb > 21 AND days_from_vb_to_vc <= 21, 1, 0) AS num_vc_21d,
        IF(days_since_vb > 21 AND days_from_vb_to_vcf <= 21, 1, 0) AS num_vcf_21d,
        IF(days_since_vb > 21 AND days_from_vb_to_vcc <= 21, 1, 0) AS num_vcc_21d,
        IF(days_since_vb > 21 AND days_from_vb_to_vu <= 21, 1, 0) AS num_vu_21d,
        IF(days_since_vb > 21 AND days_from_vb_to_os <= 21, 1, 0) AS num_os_21d,
        IF(days_since_vb > 21 AND days_from_vb_to_oa <= 21, 1, 0) AS num_oa_21d,
        IF(days_since_vb > 21 AND days_from_vb_to_cs <= 21, 1, 0) AS num_cs_21d,
        IF(days_since_vb > 28, 1, 0) AS num_vb_28d,
        IF(days_since_vb > 28 AND days_from_vb_to_vc <= 28, 1, 0) AS num_vc_28d,
        IF(days_since_vb > 28 AND days_from_vb_to_vcf <= 28, 1, 0) AS num_vcf_28d,
        IF(days_since_vb > 28 AND days_from_vb_to_vcc <= 28, 1, 0) AS num_vcc_28d,
        IF(days_since_vb > 28 AND days_from_vb_to_vu <= 28, 1, 0) AS num_vu_28d,
        IF(days_since_vb > 28 AND days_from_vb_to_os <= 28, 1, 0) AS num_os_28d,
        IF(days_since_vb > 28 AND days_from_vb_to_oa <= 28, 1, 0) AS num_oa_28d,
        IF(days_since_vb > 28 AND days_from_vb_to_cs <= 28, 1, 0) AS num_cs_28d,
        -- identifiers conversion
        IF(DATEDIFF(dim_date.date, visit_exp.dt_identifier_started) > 1, TRUE, FALSE) AS is_1d_matured,
        IF(DATEDIFF(dim_date.date, visit_exp.dt_identifier_started) > 3, TRUE, FALSE) AS is_3d_matured,
        IF(DATEDIFF(dim_date.date, visit_exp.dt_identifier_started) > 7, TRUE, FALSE) AS is_7d_matured,
        IF(DATEDIFF(dim_date.date, visit_exp.dt_identifier_started) > 14, TRUE, FALSE) AS is_14d_matured,
        IF(DATEDIFF(dim_date.date, visit_exp.dt_identifier_started) > 21, TRUE, FALSE) AS is_21d_matured,
        IF(DATEDIFF(dim_date.date, visit_exp.dt_identifier_started) > 28, TRUE, FALSE) AS is_28d_matured,
        DATEDIFF(visit_exp.dt_created, visit_exp.dt_identifier_started) AS days_from_id_to_vb,
        DATEDIFF(visit_exp.ts_visit_done, visit_exp.dt_identifier_started) AS days_from_id_to_vc,
        DATEDIFF(visit_exp.ts_visit_first_confirmed, visit_exp.dt_identifier_started) AS days_from_id_to_vcf,
        DATEDIFF(visit_exp.ts_visit_canceled, visit_exp.dt_identifier_started) AS days_from_id_to_vcc,
        DATEDIFF(visit_exp.ts_visit_unsuccessful, visit_exp.dt_identifier_started) AS days_from_id_to_vu,
        DATEDIFF(visit_exp.ts_offer_submitted, visit_exp.dt_identifier_started) AS days_from_id_to_os,
        DATEDIFF(visit_exp.ts_offer_accepted, visit_exp.dt_identifier_started) AS days_from_id_to_oa,
        DATEDIFF(visit_exp.ts_contract_signed, visit_exp.dt_identifier_started) AS days_from_id_to_cs,
        IF(is_1d_matured, sk_exp_identifier, NULL) AS number_identifiers_1d,
        IF(is_1d_matured AND days_from_id_to_vb <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_vb_1d,
        IF(is_1d_matured AND days_from_id_to_vc <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_vc_1d,
        IF(is_1d_matured AND days_from_id_to_vcf <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_vcf_1d,
        IF(is_1d_matured AND days_from_id_to_vcc <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_vcc_1d,
        IF(is_1d_matured AND days_from_id_to_vu <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_vu_1d,
        IF(is_1d_matured AND days_from_id_to_os <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_os_1d,
        IF(is_1d_matured AND days_from_id_to_oa <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_oa_1d,
        IF(is_1d_matured AND days_from_id_to_cs <= 1, sk_exp_identifier, NULL) AS number_identifiers_with_cs_1d,
        IF(is_3d_matured, sk_exp_identifier, NULL) AS number_identifiers_3d,
        IF(is_3d_matured AND days_from_id_to_vb <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_vb_3d,
        IF(is_3d_matured AND days_from_id_to_vc <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_vc_3d,
        IF(is_3d_matured AND days_from_id_to_vcf <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_vcf_3d,
        IF(is_3d_matured AND days_from_id_to_vcc <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_vcc_3d,
        IF(is_3d_matured AND days_from_id_to_vu <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_vu_3d,
        IF(is_3d_matured AND days_from_id_to_os <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_os_3d,
        IF(is_3d_matured AND days_from_id_to_oa <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_oa_3d,
        IF(is_3d_matured AND days_from_id_to_cs <= 3, sk_exp_identifier, NULL) AS number_identifiers_with_cs_3d,
        IF(is_7d_matured, sk_exp_identifier, NULL) AS number_identifiers_7d,
        IF(is_7d_matured AND days_from_id_to_vb <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_vb_7d,
        IF(is_7d_matured AND days_from_id_to_vc <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_vc_7d,
        IF(is_7d_matured AND days_from_id_to_vcf <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_vcf_7d,
        IF(is_7d_matured AND days_from_id_to_vcc <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_vcc_7d,
        IF(is_7d_matured AND days_from_id_to_vu <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_vu_7d,
        IF(is_7d_matured AND days_from_id_to_os <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_os_7d,
        IF(is_7d_matured AND days_from_id_to_oa <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_oa_7d,
        IF(is_7d_matured AND days_from_id_to_cs <= 7, sk_exp_identifier, NULL) AS number_identifiers_with_cs_7d,
        IF(is_14d_matured, sk_exp_identifier, NULL) AS number_identifiers_14d,
        IF(is_14d_matured AND days_from_id_to_vb <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_vb_14d,
        IF(is_14d_matured AND days_from_id_to_vc <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_vc_14d,
        IF(is_14d_matured AND days_from_id_to_vcf <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_vcf_14d,
        IF(is_14d_matured AND days_from_id_to_vcc <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_vcc_14d,
        IF(is_14d_matured AND days_from_id_to_vu <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_vu_14d,
        IF(is_14d_matured AND days_from_id_to_os <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_os_14d,
        IF(is_14d_matured AND days_from_id_to_oa <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_oa_14d,
        IF(is_14d_matured AND days_from_id_to_cs <= 14, sk_exp_identifier, NULL) AS number_identifiers_with_cs_14d,
        IF(is_21d_matured, sk_exp_identifier, NULL) AS number_identifiers_21d,
        IF(is_21d_matured AND days_from_id_to_vb <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_vb_21d,
        IF(is_21d_matured AND days_from_id_to_vc <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_vc_21d,
        IF(is_21d_matured AND days_from_id_to_vcf <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_vcf_21d,
        IF(is_21d_matured AND days_from_id_to_vcc <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_vcc_21d,
        IF(is_21d_matured AND days_from_id_to_vu <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_vu_21d,
        IF(is_21d_matured AND days_from_id_to_os <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_os_21d,
        IF(is_21d_matured AND days_from_id_to_oa <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_oa_21d,
        IF(is_21d_matured AND days_from_id_to_cs <= 21, sk_exp_identifier, NULL) AS number_identifiers_with_cs_21d,
        IF(is_28d_matured, sk_exp_identifier, NULL) AS number_identifiers_28d,
        IF(is_28d_matured AND days_from_id_to_vb <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_vb_28d,
        IF(is_28d_matured AND days_from_id_to_vc <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_vc_28d,
        IF(is_28d_matured AND days_from_id_to_vcf <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_vcf_28d,
        IF(is_28d_matured AND days_from_id_to_vcc <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_vcc_28d,
        IF(is_28d_matured AND days_from_id_to_vu <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_vu_28d,
        IF(is_28d_matured AND days_from_id_to_os <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_os_28d,
        IF(is_28d_matured AND days_from_id_to_oa <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_oa_28d,
        IF(is_28d_matured AND days_from_id_to_cs <= 28, sk_exp_identifier, NULL) AS number_identifiers_with_cs_28d,
        -- visit conversion by identifier
        IF(is_1d_matured AND days_from_id_to_vb <= 1, 1, 0) AS num_vb_id_1d,
        IF(is_1d_matured AND days_from_id_to_vc <= 1, 1, 0) AS num_vc_id_1d,
        IF(is_1d_matured AND days_from_id_to_vcf <= 1, 1, 0) AS num_vcf_id_1d,
        IF(is_1d_matured AND days_from_id_to_vcc <= 1, 1, 0) AS num_vcc_id_1d,
        IF(is_1d_matured AND days_from_id_to_vu <= 1, 1, 0) AS num_vu_id_1d,
        IF(is_1d_matured AND days_from_id_to_os <= 1, 1, 0) AS num_os_id_1d,
        IF(is_1d_matured AND days_from_id_to_oa <= 1, 1, 0) AS num_oa_id_1d,
        IF(is_1d_matured AND days_from_id_to_cs <= 1, 1, 0) AS num_cs_id_1d,
        IF(is_3d_matured AND days_from_id_to_vb <= 3, 1, 0) AS num_vb_id_3d,
        IF(is_3d_matured AND days_from_id_to_vc <= 3, 1, 0) AS num_vc_id_3d,
        IF(is_3d_matured AND days_from_id_to_vcf <= 3, 1, 0) AS num_vcf_id_3d,
        IF(is_3d_matured AND days_from_id_to_vcc <= 3, 1, 0) AS num_vcc_id_3d,
        IF(is_3d_matured AND days_from_id_to_vu <= 3, 1, 0) AS num_vu_id_3d,
        IF(is_3d_matured AND days_from_id_to_os <= 3, 1, 0) AS num_os_id_3d,
        IF(is_3d_matured AND days_from_id_to_oa <= 3, 1, 0) AS num_oa_id_3d,
        IF(is_3d_matured AND days_from_id_to_cs <= 3, 1, 0) AS num_cs_id_3d,
        IF(is_7d_matured AND days_from_id_to_vb <= 7, 1, 0) AS num_vb_id_7d,
        IF(is_7d_matured AND days_from_id_to_vc <= 7, 1, 0) AS num_vc_id_7d,
        IF(is_7d_matured AND days_from_id_to_vcf <= 7, 1, 0) AS num_vcf_id_7d,
        IF(is_7d_matured AND days_from_id_to_vcc <= 7, 1, 0) AS num_vcc_id_7d,
        IF(is_7d_matured AND days_from_id_to_vu <= 7, 1, 0) AS num_vu_id_7d,
        IF(is_7d_matured AND days_from_id_to_os <= 7, 1, 0) AS num_os_id_7d,
        IF(is_7d_matured AND days_from_id_to_oa <= 7, 1, 0) AS num_oa_id_7d,
        IF(is_7d_matured AND days_from_id_to_cs <= 7, 1, 0) AS num_cs_id_7d,
        IF(is_14d_matured AND days_from_id_to_vb <= 14, 1, 0) AS num_vb_id_14d,
        IF(is_14d_matured AND days_from_id_to_vc <= 14, 1, 0) AS num_vc_id_14d,
        IF(is_14d_matured AND days_from_id_to_vcf <= 14, 1, 0) AS num_vcf_id_14d,
        IF(is_14d_matured AND days_from_id_to_vcc <= 14, 1, 0) AS num_vcc_id_14d,
        IF(is_14d_matured AND days_from_id_to_vu <= 14, 1, 0) AS num_vu_id_14d,
        IF(is_14d_matured AND days_from_id_to_os <= 14, 1, 0) AS num_os_id_14d,
        IF(is_14d_matured AND days_from_id_to_oa <= 14, 1, 0) AS num_oa_id_14d,
        IF(is_14d_matured AND days_from_id_to_cs <= 14, 1, 0) AS num_cs_id_14d,
        IF(is_21d_matured AND days_from_id_to_vb <= 21, 1, 0) AS num_vb_id_21d,
        IF(is_21d_matured AND days_from_id_to_vc <= 21, 1, 0) AS num_vc_id_21d,
        IF(is_21d_matured AND days_from_id_to_vcf <= 21, 1, 0) AS num_vcf_id_21d,
        IF(is_21d_matured AND days_from_id_to_vcc <= 21, 1, 0) AS num_vcc_id_21d,
        IF(is_21d_matured AND days_from_id_to_vu <= 21, 1, 0) AS num_vu_id_21d,
        IF(is_21d_matured AND days_from_id_to_os <= 21, 1, 0) AS num_os_id_21d,
        IF(is_21d_matured AND days_from_id_to_oa <= 21, 1, 0) AS num_oa_id_21d,
        IF(is_21d_matured AND days_from_id_to_cs <= 21, 1, 0) AS num_cs_id_21d,
        IF(is_28d_matured AND days_from_id_to_vb <= 28, 1, 0) AS num_vb_id_28d,
        IF(is_28d_matured AND days_from_id_to_vc <= 28, 1, 0) AS num_vc_id_28d,
        IF(is_28d_matured AND days_from_id_to_vcf <= 28, 1, 0) AS num_vcf_id_28d,
        IF(is_28d_matured AND days_from_id_to_vcc <= 28, 1, 0) AS num_vcc_id_28d,
        IF(is_28d_matured AND days_from_id_to_vu <= 28, 1, 0) AS num_vu_id_28d,
        IF(is_28d_matured AND days_from_id_to_os <= 28, 1, 0) AS num_os_id_28d,
        IF(is_28d_matured AND days_from_id_to_oa <= 28, 1, 0) AS num_oa_id_28d,
        IF(is_28d_matured AND days_from_id_to_cs <= 28, 1, 0) AS num_cs_id_28d,
        visit_exp.dt_exp_started,
        visit_exp.dt_exp_ended,
        dim_date.date AS dt_ref
    FROM
        visit_exp
    JOIN
        dw_public.dim_date
            ON dim_date.date >= DATE(visit_exp.dt_created)
            AND dim_date.date <= visit_exp.dt_exp_ended
)
SELECT
    MD5(ec.sk_neotribe_exp || ec.sk_visit || c.metric_cohort || ec.dt_ref) AS sk_exp_visit_cohort,
    ec.sk_neotribe_exp,
    ec.sk_visit,
    ec.sk_house,
    ec.sk_visitor,
    ec.sk_owner,
    ec.sk_first_associated_agent,
    ec.sk_exp_identifier,
    ec.business_context,
    ec.exp_name_neotribe,
    ec.exp_name_experiment,
    ec.exp_identifier_type,
    ec.exp_test_group,
    c.metric_cohort,
    c.num_vb,
    c.num_vc,
    c.num_vcf,
    c.num_vcc,
    c.num_vu,
    c.num_os,
    c.num_oa,
    c.num_cs,
    c.number_identifiers,
    c.number_identifiers_with_vb,
    c.number_identifiers_with_vc,
    c.number_identifiers_with_vcf,
    c.number_identifiers_with_vcc,
    c.number_identifiers_with_vu,
    c.number_identifiers_with_os,
    c.number_identifiers_with_oa,
    c.number_identifiers_with_cs,
    c.num_vb_id,
    c.num_vc_id,
    c.num_vcf_id,
    c.num_vcc_id,
    c.num_vu_id,
    c.num_os_id,
    c.num_oa_id,
    c.num_cs_id,
    ec.dt_exp_started,
    ec.dt_exp_ended,
    ec.dt_ref
FROM
    exp_cohort AS ec
LATERAL VIEW
    STACK(
        6, -- Number of cohorts to stack

        '1d', ec.num_vb_1d, ec.num_vc_1d, ec.num_vcf_1d, ec.num_vcc_1d, ec.num_vu_1d, ec.num_os_1d, ec.num_oa_1d, ec.num_cs_1d, ec.number_identifiers_1d, ec.number_identifiers_with_vb_1d, ec.number_identifiers_with_vc_1d, ec.number_identifiers_with_vcf_1d, ec.number_identifiers_with_vcc_1d, ec.number_identifiers_with_vu_1d, ec.number_identifiers_with_os_1d, ec.number_identifiers_with_oa_1d, ec.number_identifiers_with_cs_1d, ec.num_vb_id_1d, ec.num_vc_id_1d, ec.num_vcf_id_1d, ec.num_vcc_id_1d, ec.num_vu_id_1d, ec.num_os_id_1d, ec.num_oa_id_1d, ec.num_cs_id_1d,

        '3d', ec.num_vb_3d, ec.num_vc_3d, ec.num_vcf_3d, ec.num_vcc_3d, ec.num_vu_3d, ec.num_os_3d, ec.num_oa_3d, ec.num_cs_3d, ec.number_identifiers_3d, ec.number_identifiers_with_vb_3d, ec.number_identifiers_with_vc_3d, ec.number_identifiers_with_vcf_3d, ec.number_identifiers_with_vcc_3d, ec.number_identifiers_with_vu_3d, ec.number_identifiers_with_os_3d, ec.number_identifiers_with_oa_3d, ec.number_identifiers_with_cs_3d, ec.num_vb_id_3d, ec.num_vc_id_3d, ec.num_vcf_id_3d, ec.num_vcc_id_3d, ec.num_vu_id_3d, ec.num_os_id_3d, ec.num_oa_id_3d, ec.num_cs_id_3d,

        '7d', ec.num_vb_7d, ec.num_vc_7d, ec.num_vcf_7d, ec.num_vcc_7d, ec.num_vu_7d, ec.num_os_7d, ec.num_oa_7d, ec.num_cs_7d, ec.number_identifiers_7d, ec.number_identifiers_with_vb_7d, ec.number_identifiers_with_vc_7d, ec.number_identifiers_with_vcf_7d, ec.number_identifiers_with_vcc_7d, ec.number_identifiers_with_vu_7d, ec.number_identifiers_with_os_7d, ec.number_identifiers_with_oa_7d, ec.number_identifiers_with_cs_7d, ec.num_vb_id_7d, ec.num_vc_id_7d, ec.num_vcf_id_7d, ec.num_vcc_id_7d, ec.num_vu_id_7d, ec.num_os_id_7d, ec.num_oa_id_7d, ec.num_cs_id_7d,

        '14d', ec.num_vb_14d, ec.num_vc_14d, ec.num_vcf_14d, ec.num_vcc_14d, ec.num_vu_14d, ec.num_os_14d, ec.num_oa_14d, ec.num_cs_14d, ec.number_identifiers_14d, ec.number_identifiers_with_vb_14d, ec.number_identifiers_with_vc_14d, ec.number_identifiers_with_vcf_14d, ec.number_identifiers_with_vcc_14d, ec.number_identifiers_with_vu_14d, ec.number_identifiers_with_os_14d, ec.number_identifiers_with_oa_14d, ec.number_identifiers_with_cs_14d, ec.num_vb_id_14d, ec.num_vc_id_14d, ec.num_vcf_id_14d, ec.num_vcc_id_14d, ec.num_vu_id_14d, ec.num_os_id_14d, ec.num_oa_id_14d, ec.num_cs_id_14d,

        '21d', ec.num_vb_21d, ec.num_vc_21d, ec.num_vcf_21d, ec.num_vcc_21d, ec.num_vu_21d, ec.num_os_21d, ec.num_oa_21d, ec.num_cs_21d, ec.number_identifiers_21d, ec.number_identifiers_with_vb_21d, ec.number_identifiers_with_vc_21d, ec.number_identifiers_with_vcf_21d, ec.number_identifiers_with_vcc_21d, ec.number_identifiers_with_vu_21d, ec.number_identifiers_with_os_21d, ec.number_identifiers_with_oa_21d, ec.number_identifiers_with_cs_21d, ec.num_vb_id_21d, ec.num_vc_id_21d, ec.num_vcf_id_21d, ec.num_vcc_id_21d, ec.num_vu_id_21d, ec.num_os_id_21d, ec.num_oa_id_21d, ec.num_cs_id_21d,

        '28d', ec.num_vb_28d, ec.num_vc_28d, ec.num_vcf_28d, ec.num_vcc_28d, ec.num_vu_28d, ec.num_os_28d, ec.num_oa_28d, ec.num_cs_28d, ec.number_identifiers_28d, ec.number_identifiers_with_vb_28d, ec.number_identifiers_with_vc_28d, ec.number_identifiers_with_vcf_28d, ec.number_identifiers_with_vcc_28d, ec.number_identifiers_with_vu_28d, ec.number_identifiers_with_os_28d, ec.number_identifiers_with_oa_28d, ec.number_identifiers_with_cs_28d, ec.num_vb_id_28d, ec.num_vc_id_28d, ec.num_vcf_id_28d, ec.num_vcc_id_28d, ec.num_vu_id_28d, ec.num_os_id_28d, ec.num_oa_id_28d, ec.num_cs_id_28d
    ) c AS metric_cohort, num_vb, num_vc, num_vcf, num_vcc, num_vu, num_os, num_oa, num_cs, number_identifiers, number_identifiers_with_vb, number_identifiers_with_vc, number_identifiers_with_vcf, number_identifiers_with_vcc, number_identifiers_with_vu, number_identifiers_with_os, number_identifiers_with_oa, number_identifiers_with_cs, num_vb_id, num_vc_id, num_vcf_id, num_vcc_id, num_vu_id, num_os_id, num_oa_id, num_cs_id
