WITH last_inspection_synch AS(
    SELECT
        t.id,
        MAX(ib.id_external) FILTER(WHERE ib.inspection_type = 'offboarding') AS id_exit_inspection,
        MAX(DATE(ib.ts_inspected)) AS dt_last_inspection_synch
    FROM
        datalake_terminator_clean.termination AS t
    JOIN
        datalake_inspections.inspection_booking AS ib
            ON t.id_contract = ib.id_contract
    WHERE
        ib.ts_inspected IS NOT NULL
    GROUP BY
        t.id
),
last_negociation AS (
    SELECT
        tf.id_termination,
        tfn.discount_percentage AS fee_discount_percentage,
        tfn.discount_value AS fee_discount_value,
        tfn.final_amount AS fee_final_amount,
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
        RANK() OVER (PARTITION BY tfn.id_termination_fee ORDER BY tf.id DESC) = 1
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
    SELECT
        id,
        LAST_VALUE(TO_DATE(ts_updated)) OVER (PARTITION BY id ORDER BY ts_updated ) AS dt_last_updated
    FROM
        datalake_terminator_clean.termination_aud
    GROUP BY
        1, ts_updated
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id ORDER BY ts_updated DESC) = 1
)
SELECT
    t.id AS id_termination,
    t.id_contract,
    COALESCE(t.id_exit_inspection, lis.id_exit_inspection) AS id_exit_inspection,
    ci.id_house,
    ci.id_house_listing,
    ci.id_region,
    tw.id_current_assignee AS id_workflow_assignee,
    t.cancellation_info,
    t.category,
    t.requested_by,
    t.status,
    t.feedback,
    tw.current_step AS workflow_current_step,
    ln.fee_negotiation_status,
    ln.fee_payment_option,
    t.is_relisting,
    tw.has_automatically_closed_task,
    ci.is_contract_b2b,
    (t.ts_created < ci.dt_started) AS is_before_contract_start,
    (tm.id IS NOT NULL) AS has_been_rescheduled,
    DATEDIFF(t.dt_termination, t.ts_created) AS leadtime_request_to_vacancy,
    ln.fee_discount_percentage,
    ln.fee_discount_value,
    ln.fee_final_amount,
    ln.fee_number_of_installments,
    tm.dt_last_updated AS dt_last_rescheduled,
    t.ts_created AS ts_termination_request,
    t.ts_updated AS ts_termination_updated,
    t.ts_canceled AS ts_termination_canceled,
    IF(t.status = 'DONE', t.ts_updated, NULL) AS ts_termination_finished,
    ln.ts_fee_negotiation_created,
    ln.ts_fee_negotiation_updated,
    YEAR(t.ts_updated) AS year,
    MONTH(t.ts_updated) AS month,
    DAY(t.ts_updated) AS day
FROM
    datalake_terminator_clean.termination AS t
LEFT JOIN
    datalake_terminator_clean.termination_workflow AS tw
        ON t.id = tw.id_termination
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
QUALIFY
  ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY t.ts_updated DESC) = 1
