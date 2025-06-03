WITH last_inspection_synch AS(
    SELECT
        t.id,
        ib.id_external AS id_exit_inspection,
        DATE(ib.ts_inspected) AS dt_last_inspection_synch
    FROM
        datalake_terminator_clean.termination AS t
    JOIN
        datalake_inspections.inspection_booking AS ib
            ON t.id_contract = ib.id_contract
    WHERE
        ib.ts_inspected IS NOT NULL
        AND ib.inspection_type = 'offboarding'
        AND ib.status <> 'cancelled'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY ib.ts_inspected DESC) = 1
),
last_negociation AS (
    SELECT
        tf.id_termination,
        tfn.discount_percentage AS fee_discount_percentage,
        tfn.discount_value AS fee_discount_value,
        COALESCE(tfn.final_amount, tf.landlord_amount, tf.tenant_amount) AS fee_final_amount,
        tf.tenant_payment_method:['installments'] AS fee_number_of_installments,
        tf.tenant_payment_method:['paymentOption'] AS fee_payment_option,
        tfn.status AS fee_negotiation_status,
        tfn.ts_created AS ts_fee_negotiation_created,
        tfn.ts_updated AS ts_fee_negotiation_updated
    FROM
        datalake_terminator_clean.termination_fee_negotiation AS tfn
    LEFT JOIN
        datalake_terminator_clean.termination_fee AS tf
            ON tf.id = tfn.id_termination_fee
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY tf.id_termination ORDER BY tfn.ts_updated DESC) = 1
),
contract_info AS (
    SELECT
        ctr.id AS id_contract,
        ctr.id_house,
        hl.id_house_listing,
        h.id_region,
        contract_b2b.is_contract_b2b,
        ctr.dt_started
    FROM
        datalake_ebdb_contract.contract AS ctr
    LEFT JOIN
        datalake_ebdb_listing.house_listing AS hl
            ON ctr.id = hl.id_contract
    LEFT JOIN
        datalake_ebdb_contract.contract_b2b AS contract_b2b
            ON contract_b2b.id_contract = ctr.id
    LEFT JOIN
        datalake_ebdb_clean.house AS h
            ON ctr.id_house = h.id
),
terminations_modified AS (
    WITH changes AS (
        SELECT
            id,
            dt_termination,
            ts_updated,
            LAG(dt_termination) OVER (
                PARTITION BY id
                ORDER BY rev
            ) AS prev_dt_termination
        FROM
            datalake_terminator_clean.termination_aud
        WHERE
            rev_end IS NOT NULL
    )
    SELECT DISTINCT
        id,
        TO_DATE(MAX(ts_updated) OVER (PARTITION BY id)) AS dt_last_updated
    FROM
        changes
    WHERE
        dt_termination != COALESCE(prev_dt_termination, dt_termination)
),
terminations_finished AS (
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
repair_metrics AS (
    SELECT
        id_contract,
        COUNT(CASE
          WHEN exempted_on_ar = false AND requester_type IN ('ADMIN','INSPECTIONS_SERVICE') THEN 1
        END) AS total_tentant_repair_ar,
        COUNT(CASE
          WHEN requester_type = 'OWNER' THEN 1
        END) AS repairs_added_by_owner_review,
        COUNT(CASE
          WHEN is_exempted_by_owner = true THEN 1
        END) AS repairs_exempted_by_owner_review,
        COUNT(CASE
          WHEN exempted_on_ar = false AND requester_type IN ('ADMIN','INSPECTIONS_SERVICE') THEN 1
        END) +
          COUNT(CASE
            WHEN requester_type = 'OWNER' THEN 1
          END) -
            COUNT(CASE
              WHEN is_exempted_by_owner = true THEN 1
            END) AS total_tentant_repair_review,
        COUNT(CASE
          WHEN is_finished = true AND is_exempted = true THEN 1
        END) AS repairs_exempted_ac,
        COUNT(
          CASE
            WHEN responsibility = 'ABSORBED_BY_COMPANY' AND is_exempted_by_owner = false THEN 1
        END) AS repairs_absorbed_ac,
        COUNT_IF(
          (exempted_on_ar = false AND requester_type IN ('ADMIN','INSPECTIONS_SERVICE')) OR (requester_type = 'OWNER')
        ) - COUNT_IF(
          (is_exempted_by_owner = true) OR (is_finished = true AND is_exempted = true) OR (responsibility = 'ABSORBED_BY_COMPANY' AND is_exempted_by_owner = false)
        ) AS total_tentant_repair_ac
    FROM
        datalake_inspections.repair_request
    WHERE
        comment IS NOT NULL
        AND responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
    GROUP BY
          1
)
SELECT
    t.id AS id_termination,
    t.id_contract,
    COALESCE(t.id_exit_inspection, lis.id_exit_inspection) AS id_exit_inspection,
    ci.id_house,
    ci.id_house_listing,
    ci.id_region,
    tw.id_current_assignee AS id_workflow_assignee,
    tt.id_external AS id_zendesk_task,
    t.team,
    t.cancellation_info,
    t.category,
    t.requested_by,
    t.status,
    t.feedback,
    GET_JSON_OBJECT(t.feedback, '$.reason') AS reason,
    t.rescheduling_history,
    tw.current_step AS workflow_current_step,
    ln.fee_negotiation_status,
    ln.fee_payment_option,
    checklist.checklist_item,
    cdr.decline_person,
    t.is_spoc,
    t.is_spoc_control_group,
    t.is_relisting,
    tw.has_automatically_closed_task,
    ci.is_contract_b2b,
    (t.ts_created < ci.dt_started) AS is_before_contract_start,
    (tm.id IS NOT NULL) AS has_been_rescheduled,
    checklist.is_active AS is_checklist_active,
    checklist.is_done AS is_checklist_done,
    cdr.is_relisting_enabled,
    cdr.is_early_relisting_enabled,
    neg.needs_repair_by_tenant AS has_repair_by_tenant_needed,
    DATEDIFF(t.dt_termination, t.ts_created) AS leadtime_request_to_vacancy,
    ln.fee_discount_percentage,
    ln.fee_discount_value,
    ln.fee_final_amount,
    ln.fee_number_of_installments,
    rm.total_tentant_repair_ar,
    rm.repairs_added_by_owner_review,
    rm.repairs_exempted_by_owner_review,
    rm.total_tentant_repair_review,
    rm.repairs_exempted_ac,
    rm.repairs_absorbed_ac,
    rm.total_tentant_repair_ac,
    t.spoc_wave,
    t.dt_vacancy AS dt_termination,
    tm.dt_last_updated AS dt_last_rescheduled,
    t.ts_created AS ts_termination_request,
    t.ts_updated AS ts_termination_updated,
    t.ts_canceled AS ts_termination_canceled,
    CASE
        WHEN tf.ts_termination_finished <= '2020-07-07' THEN neg.ts_updated
        WHEN tf.ts_termination_finished > '2020-07-07' THEN tf.ts_termination_finished
    END AS ts_termination_finished,
    ln.ts_fee_negotiation_created,
    ln.ts_fee_negotiation_updated,
    cdr.ts_declined,
    YEAR(t.ts_updated) AS year,
    MONTH(t.ts_updated) AS month,
    DAY(t.ts_updated) AS day
FROM
    datalake_terminator_clean.termination AS t
LEFT JOIN
    datalake_terminator_clean.termination_workflow AS tw
        ON t.id = tw.id_termination
LEFT JOIN
    datalake_terminator_clean.checklist_item AS checklist
        ON t.id = checklist.id_termination
LEFT JOIN
    datalake_terminator_clean.termination_task AS tt
        ON t.id = tt.id_termination
LEFT JOIN
    last_inspection_synch AS lis
        ON t.id = lis.id
LEFT JOIN
    last_negociation AS ln
        ON t.id = ln.id_termination
LEFT JOIN
    contract_info AS ci
        ON t.id_contract = ci.id_contract
LEFT JOIN
    terminations_modified AS tm
        ON t.id = tm.id
LEFT JOIN
    terminations_finished AS tf
        ON t.id = tf.id
        AND t.status = 'DONE'
LEFT JOIN
    datalake_ebdb_contract.contract_declined_relisting AS cdr
        ON t.id = cdr.id_termination
LEFT JOIN
    datalake_terminator_clean.negotiation AS neg
        ON t.id = neg.id_termination
LEFT JOIN
    repair_metrics AS rm
        ON t.id_contract = rm.id_contract
WHERE
    DATE(t.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY t.ts_updated DESC) = 1
