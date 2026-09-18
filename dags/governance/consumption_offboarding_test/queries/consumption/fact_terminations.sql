WITH spoc_contracts_ranked AS (
    SELECT
        id_contract,
        id_termination,
        id_worker_twilio,
        id_analyst,
        ROW_NUMBER() OVER (PARTITION BY id_contract, id_termination ORDER BY ts_updated DESC) AS rn
    FROM
        transformation_hefesto_test_curated.spoc_offboarding_contracts
),
spoc_contracts AS (
    SELECT
        id_contract,
        id_termination,
        id_worker_twilio,
        id_analyst
    FROM
        spoc_contracts_ranked
    WHERE
        rn = 1
)
SELECT
    t.id_termination AS sk_termination,
    t.id_contract AS sk_contract,
    t.id_exit_inspection AS sk_exit_inspection,
    t.id_house AS sk_house,
    t.id_house_listing AS sk_house_listing,
    t.id_region AS sk_region,
    t.id_workflow_assignee AS sk_workflow_assignee,
    BIGINT(t.id_zendesk_task) AS sk_zendesk_task,
    BIGINT(DATE_FORMAT(t.dt_termination, 'yyyyMMdd')) AS sk_termination_date,
    BIGINT(DATE_FORMAT(t.dt_original_termination, 'yyyyMMdd')) AS sk_original_termination_date,
    BIGINT(DATE_FORMAT(t.dt_last_rescheduled, 'yyyyMMdd')) AS sk_last_rescheduled_date,
    sc.id_analyst AS sk_analyst,
    sc.id_worker_twilio AS sk_worker_twilio,
    t.leadtime_request_to_vacancy,
    t.fee_discount_percentage,
    t.fee_discount_value,
    t.fee_final_amount,
    t.fee_number_of_installments,
    t.total_repairs_requested,
    t.repairs_added_by_5a_review,
    t.repairs_added_by_owner_review,
    t.total_unset_repairs,
    t.repairs_exempted_in_ar,
    t.total_tentant_repair_ar,
    t.repairs_exempted_by_owner_review,
    t.total_tentant_repair_review,
    t.total_tenant_repair_review_cost,
    t.total_tenant_repair_review_contestation_cost,
    t.total_tenant_contestation,
    t.repairs_exempted_ac,
    t.repairs_absorbed_ac,
    t.total_tentant_repair_ac,
    t.repair_cost,
    t.spoc_wave,
    t.is_spoc AS is_spoc_contract,
    t.is_spoc_eligible,
    t.is_spoc_control_group,
    t.is_relisting,
    t.has_automatically_closed_task,
    t.is_contract_b2b,
    t.is_before_contract_start,
    t.has_been_rescheduled,
    t.is_checklist_active,
    t.is_checklist_done,
    t.is_relisting_enabled,
    t.is_early_relisting_enabled,
    t.is_exit_inspection_opt_out,
    t.has_early_termination_fee,
    t.is_fee_prior_notice,
    t.has_automatic_repair_analysis,
    t.is_automatic_repair_analysis_opted_out,
    t.has_repairs,
    t.ts_termination_request,
    t.ts_termination_updated,
    t.ts_termination_canceled,
    t.ts_termination_finished,
    t.ts_fee_negotiation_created,
    t.ts_fee_negotiation_updated,
    t.ts_declined,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    transformation_terminator_test_curated.termination AS t
LEFT JOIN
    spoc_contracts AS sc
        ON t.id_contract = sc.id_contract
        AND t.id_termination = sc.id_termination
WHERE
    DATE(t.ts_termination_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
