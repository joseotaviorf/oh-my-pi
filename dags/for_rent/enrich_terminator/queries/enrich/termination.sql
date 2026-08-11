WITH raw_data AS (
  SELECT
    *,
    GET_JSON_OBJECT(rescheduling_history, '$.entries') AS entries
  FROM datalake_terminator_clean.termination
), expanded_entries AS (
  SELECT
    *,
    entry
  FROM raw_data
  LATERAL VIEW
  EXPLODE(FROM_JSON(entries, 'array<string>')) AS entry
), first_td_ranked AS (
  SELECT
    id AS id_termination,
    TO_DATE(GET_JSON_OBJECT(entry, '$.fromVacancyDate')) AS original_dt_termination,
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY TO_TIMESTAMP(GET_JSON_OBJECT(entry, '$.rescheduledAt'), 'dd/MM/yyyy HH:mm:ss') ASC) AS rn
  FROM expanded_entries
), first_td AS (
  SELECT DISTINCT
    id_termination,
    original_dt_termination
  FROM first_td_ranked
  WHERE
    rn = 1
), last_inspection_synch_ranked AS (
  SELECT
    t.id,
    ib.id_external AS id_exit_inspection,
    CAST(ib.ts_inspected AS DATE) AS dt_last_inspection_synch,
    ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY ib.ts_inspected DESC) AS rn
  FROM datalake_terminator_clean.termination AS t
  JOIN datalake_inspections.inspection_booking AS ib
    ON t.id_contract = ib.id_contract
  WHERE
    NOT ib.ts_inspected IS NULL
    AND ib.inspection_type = 'offboarding'
    AND ib.status <> 'cancelled'
), last_inspection_synch AS (
  SELECT
    id,
    id_exit_inspection,
    dt_last_inspection_synch
  FROM last_inspection_synch_ranked
  WHERE
    rn = 1
), last_negotiation_ranked AS (
  SELECT
    tf.id_termination,
    tfn.discount_percentage AS fee_discount_percentage,
    tfn.discount_value AS fee_discount_value,
    COALESCE(tfn.final_amount, tf.tenant_amount) AS fee_final_amount,
    GET_JSON_OBJECT(tf.tenant_payment_method, '$.installments') AS fee_number_of_installments,
    GET_JSON_OBJECT(tf.tenant_payment_method, '$.paymentOption') AS fee_payment_option,
    tfn.status AS fee_negotiation_status,
    CASE WHEN COALESCE(tfn.final_amount, tf.tenant_amount) > 0 THEN TRUE ELSE FALSE END AS has_early_termination_fee,
    tf.is_fee_prior_notice,
    tfn.ts_created AS ts_fee_negotiation_created,
    tfn.ts_updated AS ts_fee_negotiation_updated,
    ROW_NUMBER() OVER (PARTITION BY tf.id_termination ORDER BY tfn.ts_updated DESC) AS rn
  FROM datalake_terminator_clean.termination_fee AS tf
  LEFT JOIN datalake_terminator_clean.termination_fee_negotiation AS tfn
    ON tf.id = tfn.id_termination_fee AND tfn.status = 'CONFIRMED'
), last_negotiation AS (
  SELECT
    id_termination,
    fee_discount_percentage,
    fee_discount_value,
    fee_final_amount,
    fee_number_of_installments,
    fee_payment_option,
    fee_negotiation_status,
    has_early_termination_fee,
    is_fee_prior_notice,
    ts_fee_negotiation_created,
    ts_fee_negotiation_updated
  FROM last_negotiation_ranked
  WHERE
    rn = 1
), contract_info AS (
  SELECT
    ctr.id AS id_contract,
    ctr.id_house,
    hl.id_house_listing,
    h.id_region,
    contract_b2b.is_contract_b2b,
    ctr.dt_started
  FROM datalake_ebdb_contract.contract AS ctr
  LEFT JOIN datalake_ebdb_listing.house_listing AS hl
    ON ctr.id = hl.id_contract
  LEFT JOIN datalake_ebdb_contract.contract_b2b AS contract_b2b
    ON contract_b2b.id_contract = ctr.id
  LEFT JOIN datalake_ebdb_clean.house AS h
    ON ctr.id_house = h.id
), changes AS (
  SELECT
    id,
    dt_termination,
    ts_updated,
    LAG(dt_termination) OVER (PARTITION BY id ORDER BY rev) AS prev_dt_termination
  FROM datalake_terminator_clean.termination_aud
  WHERE
    NOT rev_end IS NULL
), terminations_modified AS (
  SELECT DISTINCT
    id,
    TO_DATE(MAX(ts_updated) OVER (PARTITION BY id)) AS dt_last_updated
  FROM changes
  WHERE
    dt_termination <> COALESCE(prev_dt_termination, dt_termination)
), terminations_finished AS (
  SELECT
    id,
    MIN(rev) AS min_rev,
    MIN(ts_updated) AS ts_termination_finished
  FROM datalake_terminator_clean.termination_aud AS ta
  WHERE
    ta.status = 'DONE'
  GROUP BY
    1
), contestation_analysis AS (
  SELECT DISTINCT
    ra.id_inspection
  FROM datalake_inspections.reviewer AS ra
  WHERE
    ra.approval_type = 'CONTESTATION_ANALYSIS'
), repair_metrics AS (
  SELECT
    rr.id_contract,
    COUNT(*) AS total_repairs_requested,
    COUNT_IF(rr.requester_type IN ('ADMIN', 'INSPECTIONS_SERVICE')) AS repairs_added_by_5a_review,
    COUNT_IF(rr.requester_type = 'OWNER') AS repairs_added_by_owner_review,
    COUNT_IF(rr.exempted_on_ar) AS repairs_exempted_in_ar,
    COUNT_IF(rr.is_exempted_by_owner = TRUE) AS repairs_exempted_by_owner_review,
    COUNT_IF(
      NOT (
        rr.has_automatically_identified IS TRUE
        AND rr.has_automatic_identification_accepted IS FALSE
      )
      AND rr.responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
      AND rr.exempted_on_ar = FALSE
      AND rr.requester_type IN ('ADMIN', 'INSPECTIONS_SERVICE')
    ) AS total_tentant_repair_ar,
    COUNT_IF(
      NOT (
        rr.has_automatically_identified IS TRUE
        AND rr.has_automatic_identification_accepted IS FALSE
      )
      AND rr.responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
      AND NOT rr.is_exempted_by_owner IS TRUE
      AND rr.exempted_on_ar = FALSE
    ) AS total_tentant_repair_review,
    SUM(
      CASE
        WHEN NOT (
          rr.has_automatically_identified IS TRUE
          AND rr.has_automatic_identification_accepted IS FALSE
        )
        AND rr.responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
        AND NOT rr.is_exempted_by_owner IS TRUE
        AND rr.exempted_on_ar = FALSE
        THEN rr.ar_cost
        ELSE 0
      END
    ) AS total_tenant_repair_review_cost,
    SUM(
      CASE
        WHEN NOT (
          rr.has_automatically_identified IS TRUE
          AND rr.has_automatic_identification_accepted IS FALSE
        )
        AND rr.responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
        AND NOT rr.is_exempted_by_owner IS TRUE
        AND rr.exempted_on_ar = FALSE
        AND rr.total_tenant_contestation > 0
        THEN rr.ar_cost
        ELSE 0
      END
    ) AS total_tenant_repair_review_contestation_cost,
    COUNT_IF(rr.total_tenant_contestation <> 0) AS total_tenant_contestation,
    COUNT_IF(rr.is_finished AND rr.is_exempted) AS repairs_exempted_ac,
    COUNT_IF(
      rr.responsibility = 'ABSORBED_BY_COMPANY' AND NOT rr.is_exempted_by_owner IS TRUE
    ) AS repairs_absorbed_ac,
    CASE
      WHEN COUNT(ca.id_inspection) > 0
      THEN COUNT_IF(
        NOT (
          rr.has_automatically_identified IS TRUE
          AND rr.has_automatic_identification_accepted IS FALSE
        )
        AND rr.responsibility IN ('TENANT', 'OWNER', 'EXEMPTED') /* ABSORBED_BY_COMPANY excluded as it is subtracted in the original logic */
        AND rr.exempted_on_ar = FALSE
        AND NOT rr.is_exempted_by_owner IS TRUE
        AND NOT (
          rr.is_finished AND rr.is_exempted
        )
      )
      ELSE 0
    END AS total_tentant_repair_ac,
    COUNT_IF(rr.responsibility IN ('UNSET', 'UNDEFINED') AND NOT rr.comment IS NULL) AS total_unset_repairs
  FROM datalake_inspections.repair_request AS rr
  LEFT JOIN contestation_analysis AS ca
    ON rr.id_inspection = ca.id_inspection
  GROUP BY
    rr.id_contract
), early_info_ranked AS (
  SELECT
    ib.id_contract,
    ib.has_early_mediation,
    b.is_early_both_agree,
    ROW_NUMBER() OVER (PARTITION BY ib.id_contract ORDER BY ib.ts_updated DESC) AS rn
  FROM datalake_inspections.inspection_booking AS ib
  LEFT JOIN datalake_inspection_services_clean.budget AS b
    ON ib.id_inspection = b.id_inspection
  WHERE
    ib.inspection_type = 'offboarding'
), early_info AS (
  SELECT
    id_contract,
    has_early_mediation,
    is_early_both_agree
  FROM early_info_ranked
  WHERE
    rn = 1
), termination_ranked AS (
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
    t.source,
    t.status,
    t.feedback,
    GET_JSON_OBJECT(t.feedback, '$.reason') AS reason,
    t.rescheduling_history,
    tw.current_step AS workflow_current_step,
    ln.fee_negotiation_status,
    ln.fee_payment_option,
    checklist.checklist_item,
    cdr.decline_person,
    tt.type AS task_type,
    t.responsible_off_manager_email,
    neg.repair_resolution,
    t.is_spoc,
    t.is_spoc_eligible,
    t.is_spoc_control_group,
    t.is_relisting,
    tw.has_automatically_closed_task,
    ci.is_contract_b2b,
    (
      t.ts_created < ci.dt_started
    ) AS is_before_contract_start,
    CASE WHEN NOT first_td.original_dt_termination IS NULL THEN TRUE ELSE FALSE END AS has_been_rescheduled,
    checklist.is_active AS is_checklist_active,
    checklist.is_done AS is_checklist_done,
    cdr.is_relisting_enabled,
    cdr.is_early_relisting_enabled,
    ioo.is_exit_inspection_opt_out,
    ln.has_early_termination_fee,
    ln.is_fee_prior_notice,
    neg.needs_repair_by_tenant AS has_repair_by_tenant_needed,
    tc.has_automatic_repair_analysis,
    tc.is_automatic_repair_analysis_opted_out,
    neg.has_landlord_comment,
    NOT ad.id_contract IS NULL AS has_bandaid,
    CASE
      WHEN rm.total_tentant_repair_ac > 0
      OR (
        rm.total_tentant_repair_ac = 0
        AND rm.total_tentant_repair_review > 0
        AND (
          ei.has_early_mediation OR ei.is_early_both_agree OR NOT ad.id_contract IS NULL
        )
      )
      OR rm.total_unset_repairs > 0
      THEN TRUE
      ELSE FALSE
    END AS has_repairs,
    DATEDIFF(TO_DATE(t.dt_termination), TO_DATE(t.ts_created)) AS leadtime_request_to_vacancy,
    ln.fee_discount_percentage,
    ln.fee_discount_value,
    ln.fee_final_amount,
    ln.fee_number_of_installments,
    rm.total_repairs_requested,
    rm.repairs_added_by_5a_review,
    rm.repairs_added_by_owner_review,
    rm.total_unset_repairs,
    rm.repairs_exempted_in_ar,
    rm.total_tentant_repair_ar,
    rm.repairs_exempted_by_owner_review,
    rm.total_tentant_repair_review,
    rm.total_tenant_repair_review_cost,
    rm.total_tenant_repair_review_contestation_cost,
    rm.total_tenant_contestation,
    rm.repairs_exempted_ac,
    rm.repairs_absorbed_ac,
    rm.total_tentant_repair_ac,
    neg.repair_cost,
    t.spoc_wave,
    t.dt_vacancy AS dt_termination,
    COALESCE(first_td.original_dt_termination, t.dt_vacancy) AS dt_original_termination,
    tm.dt_last_updated AS dt_last_rescheduled,
    t.ts_created AS ts_termination_request,
    t.ts_updated AS ts_termination_updated,
    t.ts_canceled AS ts_termination_canceled,
    CASE
      WHEN tf.ts_termination_finished <= '2020-07-07'
      THEN neg.ts_updated
      WHEN tf.ts_termination_finished > '2020-07-07'
      THEN tf.ts_termination_finished
    END AS ts_termination_finished,
    ln.ts_fee_negotiation_created,
    ln.ts_fee_negotiation_updated,
    cdr.ts_declined,
    YEAR(TO_DATE(t.ts_updated)) AS year,
    MONTH(TO_DATE(t.ts_updated)) AS month,
    DAY(TO_DATE(t.ts_updated)) AS day,
    ROW_NUMBER() OVER (PARTITION BY t.id ORDER BY t.ts_updated DESC) AS rn
  FROM datalake_terminator_clean.termination AS t
  LEFT JOIN datalake_terminator_clean.termination_workflow AS tw
    ON t.id = tw.id_termination
  LEFT JOIN datalake_terminator_clean.checklist_item AS checklist
    ON t.id = checklist.id_termination
  LEFT JOIN datalake_terminator_clean.termination_task AS tt
    ON t.id = tt.id_termination
  LEFT JOIN last_inspection_synch AS lis
    ON t.id = lis.id
  LEFT JOIN last_negotiation AS ln
    ON t.id = ln.id_termination
  LEFT JOIN contract_info AS ci
    ON t.id_contract = ci.id_contract
  LEFT JOIN terminations_modified AS tm
    ON t.id = tm.id
  LEFT JOIN terminations_finished AS tf
    ON t.id = tf.id AND t.status = 'DONE'
  LEFT JOIN datalake_ebdb_contract.contract_declined_relisting AS cdr
    ON t.id = cdr.id_termination
  LEFT JOIN datalake_terminator_clean.negotiation AS neg
    ON t.id = neg.id_termination
  LEFT JOIN repair_metrics AS rm
    ON t.id_contract = rm.id_contract
  LEFT JOIN datalake_inspections.automatic_discounts AS ad
    ON t.id_contract = ad.id_contract AND ad.discount_reviewed_value > 0
  LEFT JOIN datalake_terminator_clean.inspection_opted_out AS ioo
    ON t.id = ioo.id_termination
  LEFT JOIN datalake_terminator_clean.termination_characteristics AS tc
    ON tc.id_termination = t.id
  LEFT JOIN first_td
    ON t.id = first_td.id_termination
  LEFT JOIN early_info AS ei
    ON t.id_contract = ei.id_contract
  WHERE
    CAST(t.ts_updated AS DATE) BETWEEN CAST('{load_start_date}' AS DATE) AND CAST('{load_end_date}' AS DATE)
)
SELECT
  id_termination,
  id_contract,
  id_exit_inspection,
  id_house,
  id_house_listing,
  id_region,
  id_workflow_assignee,
  id_zendesk_task,
  team,
  cancellation_info,
  category,
  requested_by,
  source,
  status,
  feedback,
  reason,
  rescheduling_history,
  workflow_current_step,
  fee_negotiation_status,
  fee_payment_option,
  checklist_item,
  decline_person,
  task_type,
  responsible_off_manager_email,
  repair_resolution,
  is_spoc,
  is_spoc_eligible,
  is_spoc_control_group,
  is_relisting,
  has_automatically_closed_task,
  is_contract_b2b,
  is_before_contract_start,
  has_been_rescheduled,
  is_checklist_active,
  is_checklist_done,
  is_relisting_enabled,
  is_early_relisting_enabled,
  is_exit_inspection_opt_out,
  has_early_termination_fee,
  is_fee_prior_notice,
  has_repair_by_tenant_needed,
  has_automatic_repair_analysis,
  is_automatic_repair_analysis_opted_out,
  has_landlord_comment,
  has_bandaid,
  has_repairs,
  leadtime_request_to_vacancy,
  fee_discount_percentage,
  fee_discount_value,
  fee_final_amount,
  fee_number_of_installments,
  total_repairs_requested,
  repairs_added_by_5a_review,
  repairs_added_by_owner_review,
  total_unset_repairs,
  repairs_exempted_in_ar,
  total_tentant_repair_ar,
  repairs_exempted_by_owner_review,
  total_tentant_repair_review,
  total_tenant_repair_review_cost,
  total_tenant_repair_review_contestation_cost,
  total_tenant_contestation,
  repairs_exempted_ac,
  repairs_absorbed_ac,
  total_tentant_repair_ac,
  repair_cost,
  spoc_wave,
  dt_termination,
  dt_original_termination,
  dt_last_rescheduled,
  ts_termination_request,
  ts_termination_updated,
  ts_termination_canceled,
  ts_termination_finished,
  ts_fee_negotiation_created,
  ts_fee_negotiation_updated,
  ts_declined,
  year,
  month,
  day
FROM termination_ranked
WHERE
  rn = 1
