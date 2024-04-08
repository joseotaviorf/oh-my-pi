WITH terminations_finished AS (
    SELECT
        id,
        MIN(rev) AS min_rev,
        MIN(ts_updated) AS ts_termination_finished
    FROM
        datalake_terminator_clean.termination_aud AS ta
    WHERE
        ta.status = 'DONE'
    GROUP BY
        1
),
terminations_modified AS (
    SELECT
        ta1.id,
        TO_DATE(MAX(ta2.ts_updated)) AS dt_last_updated
    FROM
        datalake_terminator_clean.termination_aud AS ta1
    JOIN
        datalake_terminator_clean.termination_aud AS ta2
            ON ta2.rev = ta1.rev_end
            AND ta2.id = ta1.id
    WHERE
        ta1.rev_end IS NOT NULL
        AND ta1.dt_termination != ta2.dt_termination
    GROUP BY
        1
),
utility_attachments AS (
    SELECT
        id_termination,
        status,
        CONCAT_WS(', ',SORT_ARRAY(COLLECT_LIST(type))) AS concat_utility_attachments
    FROM
        datalake_terminator_clean.utility_bill
    GROUP BY
        id_termination, status
),
utility_in_condominium AS (
    SELECT
        id_termination,
        CONCAT_WS(', ',SORT_ARRAY(COLLECT_LIST(type))) AS utility_bill_in_condominium
    FROM
        datalake_terminator_clean.utility_bill
    WHERE
        is_included_condominium is TRUE
    GROUP BY
        id_termination
),
customer_conversions_with_multiple_answers AS (
    WITH all_customer_conversions AS (
        SELECT
            id_customer,
            id_answer,
            id_dispatch,
            id_dispatch_lot,
            customer_email,
            customer_phone,
            is_customer_identified
        FROM
            datalake_tracksale.customer_conversions
        UNION ALL
        SELECT
            id_customer,
            id_answer,
            id_dispatch,
            id_dispatch_lot,
            customer_email,
            customer_phone,
            is_customer_identified
        FROM
            datalake_casa_mineira_tracksale.customer_conversions
    ),
    all_dispatch AS (
        SELECT
            id,
            id_campaign,
            status,
            ts_created
        FROM
            datalake_tracksale.dispatch
        UNION ALL
        SELECT
            id,
            id_campaign,
            status,
            ts_created
        FROM
            datalake_casa_mineira_tracksale.dispatch
    ),
    all_answer AS (
        SELECT
            id,
            nps_answer,
            nps_comment,
            seconds_spent_answering,
            score_category,
            ts_answer_sent_local
        FROM
            datalake_tracksale.answer
        UNION ALL
        SELECT
            id,
            nps_answer,
            nps_comment,
            seconds_spent_answering,
            score_category,
            ts_answer_sent_local
        FROM
            datalake_casa_mineira_tracksale.answer
    )
    SELECT
        COALESCE(ansd.id_contract, -1) AS id_contract,
        disp.id_campaign,
        COALESCE(cc.id_customer,-1) AS id_customer,
        cc.id_dispatch,
        cc.id_dispatch_lot,
        COALESCE(cc.id_answer,-1) AS id_nps_answer,
        cc.customer_email,
        cc.customer_phone,
        disp.status,
        ans.score_category,
        ans.nps_answer,
        ans.nps_comment,
        ROUND(ans.seconds_spent_answering/60.0,2) AS minutes_spent_answering,
        cc.id_answer IS NOT NULL AS is_answered,
        cc.is_customer_identified,
        disp.ts_created,
        ans.ts_answer_sent_local
    FROM
        all_customer_conversions AS cc
    JOIN
        all_dispatch AS disp
            ON cc.id_dispatch_lot = disp.id
    LEFT JOIN
        all_answer AS ans
            ON cc.id_answer = ans.id
    LEFT JOIN
        datalake_nps_answer_drivers.answer_drivers ansd
            ON cc.id_answer = ansd.id_answer
),
customer_conversions_last_answers AS (
    WITH last_answer AS (
        SELECT
            id_contract,
            MAX(ts_created) AS max_ts_created,
            MAX(ts_answer_sent_local) AS max_ts_answer_sent_local
        FROM
            customer_conversions_with_multiple_answers
        GROUP BY
            id_contract
    )
    SELECT
        ccmulti.*
    FROM
        customer_conversions_with_multiple_answers ccmulti
    JOIN
        last_answer
            ON last_answer.id_contract = ccmulti.id_contract
            AND last_answer.max_ts_created = ccmulti.ts_created
            AND last_answer.max_ts_answer_sent_local = ccmulti.ts_answer_sent_local
),
campaign AS (
    SELECT
        id,
        customer_type,
        campaign_name,
        metric_group
    FROM
        datalake_tracksale.campaign
    UNION ALL
    SELECT
        id,
        customer_type,
        campaign_name,
        metric_group
    FROM
        datalake_casa_mineira_tracksale.campaign
),
total_nps AS (
    SELECT
        term.id,
        100.0 * (COUNT(DISTINCT
            CASE
                WHEN cc.nps_answer BETWEEN 9 AND 10 THEN cc.id_nps_answer
            END
        ) - COUNT(DISTINCT
            CASE
                WHEN cc.nps_answer BETWEEN 0 AND 6 THEN cc.id_nps_answer
            END
        )) / NULLIF(COUNT(DISTINCT
            CASE
                WHEN cc.id_nps_answer > 0 THEN cc.id_nps_answer
            END
        ) , 0) AS NPS
    FROM
        datalake_terminator_clean.termination AS term
    JOIN
        customer_conversions_with_multiple_answers AS cc
            ON cc.id_contract = term.id_contract
    LEFT JOIN
        campaign AS cmp
            ON cc.id_campaign = cmp.id
    WHERE
        term.status <> 'CANCELED'
        AND cmp.metric_group IN ('iqoffboarding', 'ppoffboarding', 'offboarding')
    GROUP BY
        term.id
),
iq_nps AS (
    SELECT
        term.id,
        100.0 * (COUNT(DISTINCT
            CASE
                WHEN cc.nps_answer BETWEEN 9 AND 10 THEN cc.id_nps_answer
            END
        ) - COUNT(DISTINCT
            CASE
                WHEN cc.nps_answer BETWEEN 0 AND 6 THEN cc.id_nps_answer
            END
        )) / NULLIF(COUNT(DISTINCT
            CASE
                WHEN cc.id_nps_answer > 0 THEN cc.id_nps_answer
            END
        ) , 0) AS IQ_NPS
    FROM
        datalake_terminator_clean.termination term
    JOIN
        customer_conversions_with_multiple_answers AS cc
            ON cc.id_contract = term.id_contract
    LEFT JOIN
        campaign AS cmp
            ON cc.id_campaign = cmp.id
    WHERE
        term.status <> 'CANCELED'
        AND cmp.metric_group IN ('iqoffboarding', 'offboarding')
        AND cmp.customer_type = 'IQ'
    GROUP BY
        term.id
),
pp_nps AS (
    SELECT
        term.id,
        100.0 * (COUNT(DISTINCT
            CASE
                WHEN cc.nps_answer BETWEEN 9 AND 10 THEN cc.id_nps_answer
            END
        ) - COUNT(DISTINCT
            CASE
                WHEN cc.nps_answer BETWEEN 0 AND 6 THEN cc.id_nps_answer
            END
        )) / NULLIF(COUNT(DISTINCT
            CASE
                WHEN cc.id_nps_answer > 0 THEN cc.id_nps_answer
            END
        ) , 0) AS PP_NPS
    FROM
        datalake_terminator_clean.termination term
    JOIN
        customer_conversions_with_multiple_answers AS cc
            ON cc.id_contract = term.id_contract
    LEFT JOIN
        campaign AS cmp
            ON cc.id_campaign = cmp.id
    WHERE
        term.status <> 'CANCELED'
        AND cmp.metric_group IN ('ppoffboarding', 'offboarding')
        AND cmp.customer_type = 'PP'
    GROUP BY
        term.id
),
last_inspection_synch AS(
    SELECT
        term.id,
        MAX(insp.id_external) FILTER(WHERE insp.inspection_type = 'offboarding') AS id_exit_inspection,
        MAX(DATE(insp.ts_inspected)) AS dt_last_inspection_synch
    FROM
        datalake_terminator_clean.termination AS term
    JOIN
        datalake_inspections.inspection_booking insp
            ON term.id_contract = insp.id_contract
    WHERE
        term.status <> 'CANCELED'
        AND insp.ts_inspected IS NOT NULL
    GROUP BY
        term.id
),
application_user_info AS (
    SELECT
        tf.id AS id_termination,
        au.id_external,
        au.name,
        au.email
    FROM
        terminations_finished AS tf
    JOIN
        datalake_terminator_clean.rev_info AS ri
            ON ri.rev = tf.min_rev
    LEFT JOIN
        datalake_terminator_clean.application_user AS au
            ON au.id = ri.id_user
    WHERE
        id_external IS NOT NULL
),
negotiation_rank AS (
    SELECT
        id_termination_fee,
        id AS id_fee_negotiation,
        discount_percentage,
        discount_value,
        final_amount,
        status,
        ts_created,
        ts_updated,
        RANK() OVER (PARTITION BY id_termination_fee ORDER BY id DESC) AS fee_negotiation_rank
    FROM
        datalake_terminator_clean.termination_fee_negotiation
),
last_negotiation AS (
    SELECT
        tf.id_termination,
        nr.discount_percentage AS fee_discount_percentage,
        nr.discount_value AS fee_discount_value,
        nr.final_amount AS fee_final_amount,
        tf.tenant_payment_method:['installments'] AS fee_number_of_installments,
        tf.tenant_payment_method:['paymentOption'] AS fee_payment_option,
        nr.status AS fee_negotiation_status,
        nr.ts_created AS ts_fee_negotiation_created,
        nr.ts_updated AS ts_fee_negotiation_updated
    FROM
        negotiation_rank AS nr
    LEFT JOIN
        datalake_terminator_clean.termination_fee AS tf
            ON nr.id_termination_fee = tf.id
    WHERE
        fee_negotiation_rank = 1
),
contract_info AS (
    WITH house_b2b_portability AS (
        SELECT
            hl.id_house_listing
        FROM
            datalake_ebdb_listing.house_listing AS hl
        JOIN
            datalake_ebdb_clean.house AS hse
                ON hse.id = hl.id_house
        JOIN
            datalake_ebdb_listing.portability AS prt
                ON prt.id_house = hl.id_house
                AND prt.is_owner_b2b
        WHERE
            prt.ts_created BETWEEN COALESCE(hl.ts_listing_version_start, '1900-01-01 00:00:00')
            AND COALESCE(hl.ts_listing_version_end, NOW())
    )
    SELECT
        ctr.id AS id_contract,
        ctr.id_house,
        hl.id_house_listing,
        ctr.status AS contract_status,
        contract_b2b.b2b_type,
        contract_b2b.b2b_prime_type,
        contract_b2b.is_contract_b2b,
        (hp.id_house_listing IS NOT NULL) OR contract_b2b.is_b2b AS is_b2b,
        ctr.is_exit_inspection_opted_out,
        ctr.dt_started AS dt_start,
        ctr.dt_entered AS dt_entrance,
        TO_TIMESTAMP(ctr.ts_analyst_annulment_input) AS ts_analyst_annulment_input,
        ctr.ts_created,
        ctr.ts_updated
    FROM
        datalake_ebdb_contract.contract ctr
    LEFT JOIN
        datalake_ebdb_listing.house_listing hl
            ON ctr.id = hl.id_contract
    LEFT JOIN
        datalake_ebdb_contract.contract_b2b contract_b2b
            ON contract_b2b.id_contract = ctr.id
    LEFT JOIN
        house_b2b_portability hp
            ON hp.id_house_listing = hl.id_house_listing
),
house_region AS (
    SELECT
        ctrt.id,
        house.id_region
    FROM
        datalake_ebdb_clean.contract AS ctrt
    LEFT JOIN
        datalake_ebdb_clean.house
            ON ctrt.id_house = house.id
),
termination_attachments AS (
  SELECT
    id_termination,
    COLLECT_SET(type) AS attachment_type_list
  FROM
    datalake_terminator_clean.attachment
  GROUP BY 1
)
SELECT
    term.id AS id_termination,
    aui.id_external AS id_application_user,
    term.id_contract,
    COALESCE(term.id_exit_inspection, lis.id_exit_inspection) AS id_exit_inspection,
    ci.id_house,
    ci.id_house_listing,
    COALESCE(house.id_region, -1) AS id_region,
    tw.id_current_assignee AS id_workflow_assignee,
    cc.id_nps_answer,
    cc.id_dispatch_lot,
    cc.score_category,
    cc.customer_email,
    cc.customer_phone,
    cc.nps_comment,
    cc.status AS dispatch_status,
    ci.contract_status,
    cmp.customer_type,
    cmp.campaign_name,
    term.cancellation_info,
    term.category,
    term.feedback,
    GET_JSON_OBJECT(term.feedback, '$.churnInfo.reason') AS churn_reason,
    GET_JSON_OBJECT(term.feedback, '$.nextProperty') AS next_property,
    GET_JSON_OBJECT(term.feedback, '$.propertyIssue') AS property_issue,
    GET_JSON_OBJECT(term.feedback, '$.reason') AS reason,
    term.requested_by,
    term.rescheduling_history,
    term.status,
    term.source,
    CASE
        WHEN (source = 'PWA' AND ci.is_b2b = 'true' AND term.ts_created < '2020-06-10')
            OR (source = 'PWA' AND term.dt_termination < ci.dt_entrance)
            OR (source = 'PWA' AND GET_JSON_OBJECT(feedback, '$.reason') = 'JOB_TRANSFER' AND term.ts_created >= '2020-03-25' AND ADD_MONTHS(ci.dt_entrance, 12) > term.dt_termination)
            OR (source = 'PWA' AND GET_JSON_OBJECT(feedback, '$.reason') = 'JOB_TRANSFER' AND term.ts_created < '2020-03-25') THEN 'Semi-automatic'
        WHEN term.source = 'CRM' THEN 'Manual'
        ELSE 'Automatic'
    END AS type,
    GET_JSON_OBJECT(term.tenant_keys_location, '$.location') AS tenant_key_location,
    GET_JSON_OBJECT(term.tenant_pending_tasks, '$.sendUtilityBillsReceipt') AS send_utility_bills_receipt,
    term.tenant_keys_location AS tenant_key_detail,
    term.owner_keys_location AS owner_key_detail,
    term.utility_bill_info,
    aui.name AS application_user_name,
    aui.email AS application_user_email,
    ci.b2b_type,
    ci.b2b_prime_type,
    at.attachment_type_list,
    neg.repair_resolution,
    ln.fee_payment_option,
    ln.fee_negotiation_status,
    cua.concat_utility_attachments AS completed_utility_attachments,
    pua.concat_utility_attachments AS pending_utility_attachments,
    uic.utility_bill_in_condominium,
    tw.current_step AS workflow_current_step,
    tn.nps,
    iqn.iq_nps,
    ppn.pp_nps,
    neg.repair_cost,
    ln.fee_discount_percentage,
    ln.fee_discount_value,
    ln.fee_final_amount,
    ln.fee_number_of_installments,
    DATEDIFF(term.dt_termination, term.ts_created) AS leadtime_request_to_vacancy,
    CASE
        WHEN tf.ts_termination_finished <= '2020-07-07' THEN DATEDIFF(neg.ts_updated, term.dt_termination)
        WHEN tf.ts_termination_finished > '2020-07-07' THEN DATEDIFF(tf.ts_termination_finished, term.dt_termination)
    END AS leadtime_vacancy_to_finish,
    ci.is_b2b,
    ci.is_contract_b2b,
    (term.ts_created < ci.dt_start) AS is_before_contract_start,
    term.has_exit_inspection,
    neg.has_landlord_comment AS has_repairs,
    neg.needs_repair_by_tenant AS is_repair_tenant_duty,
    DATE_TRUNC('DD',term.dt_termination) < ADD_MONTHS(DATE_TRUNC('DD',term.ts_created), 1) AS has_prior_notice_fine,
    DATE_TRUNC('DD',term.dt_termination) < ADD_MONTHS(DATE_TRUNC('DD',ci.dt_start), 12) AS has_one_year_fine,
    (tm.id IS NOT NULL) AS has_been_rescheduled,
    (term.ts_canceled IS NOT NULL) AS is_termination_canceled,
    (tw.id IS NOT NULL) AS is_workflow,
    term.is_relisting,
    cc.is_answered,
    ci.is_exit_inspection_opted_out,
    tw.has_automatically_closed_task,
    term.dt_vacancy AS dt_termination,
    term.dt_ended_termination,
    tm.dt_last_updated AS dt_last_rescheduled,
    TO_DATE(lis.dt_last_inspection_synch) AS dt_last_inspection_synched,
    ci.dt_start AS dt_contract_started,
    ci.dt_entrance AS dt_contract_entrance,
    ci.ts_analyst_annulment_input,
    cc.ts_answer_sent_local AS ts_nps_answer_sent,
    neg.ts_updated AS ts_negotiation_updated,
    ln.ts_fee_negotiation_created,
    ln.ts_fee_negotiation_updated,
    term.ts_created,
    term.ts_canceled,
    CASE
        WHEN tf.ts_termination_finished <= '2020-07-07' THEN neg.ts_updated
        WHEN tf.ts_termination_finished > '2020-07-07' THEN tf.ts_termination_finished
    END AS ts_termination_finished,
    term.ts_updated,
    NOW() as ts_load
FROM
    datalake_terminator_clean.termination term
LEFT JOIN
    terminations_finished AS tf
        ON tf.id = term.id
        AND term.status = 'DONE'
LEFT JOIN
    datalake_terminator_clean.negotiation neg
        ON term.id = neg.id_termination
LEFT JOIN
    terminations_modified AS tm
        ON tm.id = term.id
LEFT JOIN
    contract_info AS ci
        ON ci.id_contract = term.id_contract
LEFT JOIN
    datalake_terminator_clean.termination_workflow AS tw
        ON term.id = tw.id_termination
LEFT JOIN
    house_region AS house
        ON house.id = term.id_contract
LEFT JOIN
    utility_attachments AS cua
        ON cua.id_termination = term.id
        AND cua.status = 'COMPLETED'
LEFT JOIN
    utility_attachments AS pua
        ON pua.id_termination = term.id
        AND pua.status = 'PENDING'
LEFT JOIN
    utility_in_condominium AS uic
        ON uic.id_termination = term.id
LEFT JOIN
    total_nps AS tn
        ON tn.id = term.id
LEFT JOIN
    iq_nps AS iqn
        ON iqn.id = term.id
LEFT JOIN
    pp_nps AS ppn
        ON ppn.id = term.id
LEFT JOIN
    last_inspection_synch AS lis
        ON lis.id = term.id
LEFT JOIN
    application_user_info AS aui
        ON term.id = aui.id_termination
LEFT JOIN
    last_negotiation AS ln
        ON term.id = ln.id_termination
LEFT JOIN
    customer_conversions_last_answers AS cc
        ON cc.id_contract = term.id_contract
LEFT JOIN
    campaign AS cmp
        ON cc.id_campaign = cmp.id
LEFT JOIN
    termination_attachments AS at
        ON term.id = at.id_termination