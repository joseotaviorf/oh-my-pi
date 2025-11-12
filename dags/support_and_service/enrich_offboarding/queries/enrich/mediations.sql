WITH report_approvas AS (
  SELECT
    ra.id_inspection,
    ra.is_early_both_agree,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.owner_approved END AS has_owner_approved_budget_approval,
    CASE WHEN ra.approval_type = 'BUDGET_APPROVAL' THEN ra.tenant_approved END AS has_tenant_approved_budget_approval
  FROM
    datalake_inspections.report_approvals AS ra
),
inspection as (
  SELECT
      ib.id_contract,
      ib.has_early_mediation,
      ra.is_early_both_agree,
      CASE
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval = TRUE
            AND ra.has_tenant_approved_budget_approval = FALSE THEN 'LL Agreed TT Disagreed'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval = TRUE
            AND ra.has_tenant_approved_budget_approval IS NULL THEN 'LL Agreed TT no answer'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval = FALSE
            AND ra.has_tenant_approved_budget_approval IS NULL THEN 'LL Disagreed TT no answer'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval = FALSE
            AND ra.has_tenant_approved_budget_approval = TRUE THEN 'LL Disagreed TT Agreed'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval IS NULL
            AND ra.has_tenant_approved_budget_approval = TRUE THEN 'TT Agreed LL no answer'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval IS NULL
            AND ra.has_tenant_approved_budget_approval = FALSE THEN 'TT Disagreed LL no answer'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval = TRUE
            AND ra.has_tenant_approved_budget_approval = TRUE THEN 'Both Agreed'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval = FALSE
            AND ra.has_tenant_approved_budget_approval = FALSE THEN 'Both Disagreed'
          WHEN isc.ts_budget_approval_sent_to_owner IS NOT NULL
            AND ra.has_owner_approved_budget_approval IS NULL
            AND ra.has_tenant_approved_budget_approval IS NULL THEN 'Both no answer'
          ELSE NULL
      END AS type_ba
  FROM
      datalake_inspections.inspection_booking AS ib
  LEFT JOIN
      report_approvas AS ra
          ON ib.id_inspection = ra.id_inspection
  LEFT JOIN
      datalake_inspections.inspection_status_change AS isc
          ON ib.id_inspection = isc.id_inspection
  WHERE
      ib.inspection_type = 'offboarding'
  QUALIFY
      ROW_NUMBER() OVER(PARTITION BY ib.id_contract ORDER BY ib.ts_updated DESC) = 1
),
unset_repairs AS (
  SELECT
    rr.id_contract,
    COUNT_IF(rr.responsibility IN ('UNSET', 'UNDEFINED') AND rr.comment IS NOT NULL) AS total_unset_repairs
  FROM
    datalake_inspections.repair_request AS rr
  GROUP BY ALL
),
terminations AS (
  SELECT
    t.id_termination,
    t.id_contract,
    i.type_ba,
    c.rent,
    t.repairs_absorbed_ac,
    t.total_tentant_repair_ac,
    ur.total_unset_repairs,
    tc.is_pro_owner,
    CASE
      WHEN DATE(ib.ts_synced - INTERVAL 3 HOUR) > DATE(t.ts_termination_request) THEN DATE(ib.ts_synced - INTERVAL 3 HOUR)
      ELSE NULL
    END dt_inspection,
    t.ts_termination_request,
    t.ts_termination_finished
  FROM
    datalake_terminator.termination AS t
  LEFT JOIN
    datalake_terminator_clean.termination_characteristics AS tc
      ON t.id_termination = tc.id_termination
  LEFT JOIN
    datalake_ebdb_contract.contract AS c
      ON t.id_contract = c.id
  LEFT JOIN
    datalake_inspections.inspection_booking AS ib
      ON t.id_contract = ib.id_contract
  LEFT JOIN
    unset_repairs AS ur
      ON t.id_contract = ur.id_contract
  LEFT JOIN
    inspection AS i
      ON t.id_contract = i.id_contract
  WHERE
    t.status != 'CANCELED'
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY t.id_contract ORDER BY
      CASE
        WHEN DATE(ib.ts_synced - INTERVAL '3' HOUR) > DATE(t.ts_termination_request) THEN DATE(ib.ts_synced - INTERVAL '3' HOUR) ELSE NULL
      END DESC, t.ts_termination_request DESC
    ) = 1
),

mediation_via_terminator AS (
  SELECT
    ts.id_termination,
    t.id_contract,
    tc.id_ticket,
    CASE
      WHEN ts.id_external IS NULL THEN NULL
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND t.is_pro_owner = TRUE THEN 'Squad 6 - PP Multi'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND t.rent >= 2500 THEN 'Squad 5 - High Value'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND t.rent < 2500 AND t.is_pro_owner = FALSE AND t.type_ba = 'Both Agreed' THEN 'Squad 1 - Both Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND (t.rent < 2500 AND t.is_pro_owner = FALSE) AND (t.type_ba = 'LL Agreed TT Disagreed' OR t.type_ba = 'LL Agreed TT no answer') THEN 'Squad 2 - PP Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND (t.rent < 2500 AND t.is_pro_owner = FALSE) AND (t.type_ba = 'LL Disagreed TT Agreed' OR t.type_ba = 'TT Agreed LL no answer') THEN 'Squad 3 - IQ Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND (t.rent >= 2500 OR t.is_pro_owner = TRUE) THEN 'Squad 5 - High Value e PP Multi'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND t.rent < 2500 AND t.is_pro_owner = FALSE AND t.type_ba = 'Both Agreed' THEN 'Squad 1 - Both Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND (t.rent < 2500 AND t.is_pro_owner = FALSE) AND (t.type_ba = 'LL Agreed TT Disagreed' OR t.type_ba = 'LL Agreed TT no answer') THEN 'Squad 2 - PP Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND (t.rent < 2500 AND t.is_pro_owner = FALSE) AND (t.type_ba = 'LL Disagreed TT Agreed' OR t.type_ba = 'TT Agreed LL no answer') THEN 'Squad 3 - IQ Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR < DATE('2024-12-06') AND t.type_ba = 'Both Agreed' THEN 'Squad 1 - Both Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR < DATE('2024-12-06') AND (t.rent < 2500 AND t.is_pro_owner = FALSE) AND (t.type_ba = 'LL Agreed TT Disagreed' OR t.type_ba = 'LL Agreed TT no answer') THEN 'Squad 2 - PP Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR < DATE('2024-12-06') AND (t.rent < 2500 AND t.is_pro_owner = FALSE) AND (t.type_ba = 'LL Disagreed TT Agreed' OR t.type_ba = 'TT Agreed LL no answer') THEN 'Squad 3 - IQ Agreed'
      ELSE 'Squad 4 - LL and TT Disagreed or no answer'
    END squad
  FROM
    datalake_terminator_clean.termination_task AS ts
  LEFT JOIN
    terminations AS t
      ON t.id_termination = ts.id_termination
  LEFT JOIN
    datalake_zendesk.tickets_current AS tc
      ON ts.id_external = tc.id_ticket
  WHERE
    ts.type = 'TERMINATION_LANDLORD'
    AND tc.tags NOT LIKE '%ezsend_one%'
    AND tc.tags NOT LIKE '%closed_by_merge%'
    AND tc.tags NOT LIKE '%ticket_acompanhamento%'
    AND tc.group_name = 'Offboarding Reparos [OFF] [POS] [BACK]'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY tc.id_contract ORDER BY tc.ts_created DESC) = 1
),

mediation_via_zendesk AS (
  SELECT
    tc.id_ticket,
    tc.id_contract,
    CASE
      WHEN tc.id_ticket IS NULL THEN NULL
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND trm.is_pro_owner = TRUE THEN 'Squad 6 - PP Multi'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND trm.rent >= 2500 THEN 'Squad 5 - High Value'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND trm.rent < 2500 AND trm.is_pro_owner = FALSE AND trm.type_ba = 'Both Agreed' THEN 'Squad 1 - Both Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND (trm.rent < 2500 AND trm.is_pro_owner = FALSE) AND (trm.type_ba = 'LL Agreed TT Disagreed' OR trm.type_ba = 'LL Agreed TT no answer') THEN 'Squad 2 - PP Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2025-03-06') AND (trm.rent < 2500 AND trm.is_pro_owner = FALSE) AND (trm.type_ba = 'LL Disagreed TT Agreed' OR trm.type_ba = 'TT Agreed LL no answer') THEN 'Squad 3 - IQ Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND (trm.rent >= 2500 OR trm.is_pro_owner = TRUE) THEN 'Squad 5 - High Value e PP Multi'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND trm.rent < 2500 AND trm.is_pro_owner = FALSE AND trm.type_ba = 'Both Agreed' THEN 'Squad 1 - Both Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND (trm.rent < 2500 AND trm.is_pro_owner = FALSE) AND (trm.type_ba = 'LL Agreed TT Disagreed' OR trm.type_ba = 'LL Agreed TT no answer') THEN 'Squad 2 - PP Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR >= DATE('2024-12-06') AND (trm.rent < 2500 AND trm.is_pro_owner = FALSE) AND (trm.type_ba = 'LL Disagreed TT Agreed' OR trm.type_ba = 'TT Agreed LL no answer') THEN 'Squad 3 - IQ Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR < DATE('2024-12-06') AND trm.type_ba = 'Both Agreed' THEN 'Squad 1 - Both Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR < DATE('2024-12-06') AND (trm.rent < 2500 AND trm.is_pro_owner = FALSE) AND (trm.type_ba = 'LL Agreed TT Disagreed' OR trm.type_ba = 'LL Agreed TT no answer') THEN 'Squad 2 - PP Agreed'
      WHEN tc.ts_created - INTERVAL 3 HOUR < DATE('2024-12-06') AND (trm.rent < 2500 AND trm.is_pro_owner = FALSE) AND (trm.type_ba = 'LL Disagreed TT Agreed' OR trm.type_ba = 'TT Agreed LL no answer') THEN 'Squad 3 - IQ Agreed'
      ELSE 'Squad 4 - LL and TT Disagreed or no answer'
    END squad
  FROM
    datalake_zendesk.tickets_current AS tc
  LEFT JOIN
    terminations AS trm
      ON tc.id_contract = trm.id_contract
  WHERE
    tc.tags NOT LIKE '%ezsend_one%'
    AND tc.tags NOT LIKE '%closed_by_merge%'
    AND tc.tags NOT LIKE '%ticket_acompanhamento%'
    AND tc.group_name = 'Offboarding Reparos [OFF] [POS] [BACK]'
    AND COALESCE(tc.custom_fields['Tipo de Cliente [PRE-SAIDA]'], tc.custom_fields['Tipo de Cliente']) LIKE '%proprietário%'
    AND tc.custom_fields['Tipo de Demanda'] = 'demanda_pos_saida'
  QUALIFY
    ROW_NUMBER() OVER(PARTITION BY tc.id_contract ORDER BY tc.ts_created DESC) = 1
)

SELECT
  t.id_termination,
  t.id_contract,
  COALESCE(mtr.id_ticket, STRING(mtk.id_ticket)) AS id_mediation_ticket,
  COALESCE(mtr.squad, mtk.squad) AS squad,
  CASE
    WHEN t.ts_termination_finished IS NULL THEN NULL
    WHEN t.total_tentant_repair_ac > 0 THEN TRUE
    ELSE FALSE
  END has_ac_repairs,
  t.total_unset_repairs > 0 AS has_unset_repairs,
  i.has_early_mediation,
  i.is_early_both_agree,
  COALESCE(mtr.id_ticket, STRING(mtk.id_ticket)) IS NOT NULL AS has_mediation_ticket,
  IF(
    (t.total_tentant_repair_ac > 0 AND i.type_ba != 'Both Agreed')
    OR i.has_early_mediation
    OR t.total_unset_repairs > 0
    , TRUE, FALSE
  ) AS has_mediation,
  mtr.id_ticket IS NOT NULL AS is_ticket_opened_via_terminator,
  t.dt_inspection,
  t.ts_termination_request,
  t.ts_termination_finished
FROM
  terminations AS t
LEFT JOIN
  mediation_via_terminator AS mtr
    ON t.id_termination = mtr.id_termination
LEFT JOIN
  mediation_via_zendesk AS mtk
    ON t.id_contract = mtk.id_contract
LEFT JOIN
  inspection AS i
    ON t.id_contract = i.id_contract
