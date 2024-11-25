WITH repair_metrics AS (
    SELECT
        id_contract,
        id_inspection,
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
        COUNT(
          CASE
            WHEN exempted_on_ar = false AND requester_type IN ('ADMIN','INSPECTIONS_SERVICE') THEN 1
        END) +
            COUNT(CASE
              WHEN requester_type = 'OWNER' THEN 1
            END) -
              COUNT(CASE
                WHEN is_exempted_by_owner = true THEN 1
              END) -
                COUNT(
                  CASE
                    WHEN is_finished = true AND is_exempted = true THEN 1
                END) -
                  COUNT(CASE
                    WHEN responsibility = 'ABSORBED_BY_COMPANY' AND is_exempted_by_owner = false THEN 1
                  END) AS total_tentant_repair_ac
    FROM
        datalake_inspections.repair_request
    WHERE
        comment IS NOT NULL
        AND responsibility IN ('TENANT', 'OWNER', 'ABSORBED_BY_COMPANY', 'EXEMPTED')
    GROUP BY
          ALL
),
contract_repair_metrics AS (
    SELECT
        id_contract,
        id_inspection,
        total_tentant_repair_ar,
        repairs_added_by_owner_review,
        repairs_exempted_by_owner_review,
        total_tentant_repair_review,
        repairs_exempted_ac,
        repairs_absorbed_ac,
        total_tentant_repair_ac
    FROM
        repair_metrics
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY id_inspection DESC) = 1
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
    BIGINT(DATE_FORMAT(t.dt_last_rescheduled, 'yyyyMMdd')) AS sk_last_rescheduled_date,
    t.leadtime_request_to_vacancy,
    t.fee_discount_percentage,
    t.fee_discount_value,
    t.fee_final_amount,
    t.fee_number_of_installments,
    crm.total_tentant_repair_ar,
    crm.repairs_added_by_owner_review,
    crm.repairs_exempted_by_owner_review,
    crm.total_tentant_repair_review,
    crm.repairs_exempted_ac,
    crm.repairs_absorbed_ac,
    crm.total_tentant_repair_ac,
    t.is_relisting,
    t.has_automatically_closed_task,
    t.is_contract_b2b,
    t.is_before_contract_start,
    t.has_been_rescheduled,
    t.is_checklist_active,
    t.is_checklist_done,
    t.ts_termination_request,
    t.ts_termination_updated,
    t.ts_termination_canceled,
    t.ts_termination_finished,
    t.ts_fee_negotiation_created,
    t.ts_fee_negotiation_updated,
    NOW() AS ts_load,
    year,
    month,
    day
FROM
    datalake_terminator.termination AS t
LEFT JOIN
    contract_repair_metrics AS crm
      ON t.id_contract = crm.id_contract
WHERE
    DATE(t.ts_termination_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
