WITH terminations AS (
  SELECT DISTINCT
    ct.id_termination,
    ct.id_contract,
    t.repairs_absorbed_ac,
    t.total_tentant_repair_ac,
    CASE 
      WHEN DATE(ib.ts_synced - INTERVAL 3 HOUR) > DATE(ct.ts_created) THEN DATE(ib.ts_synced - INTERVAL 3 HOUR)
      ELSE NULL
    END dt_inspection,
    ct.ts_created AS ts_termination_request,
    ct.ts_updated AS ts_termination_updated,
    ct.ts_termination_finished,
    ib.ts_synced
  FROM
    datalake_offboarding.contract_termination AS ct
  LEFT JOIN
    datalake_terminator.termination AS t
      ON t.id_termination = ct.id_termination
  LEFT JOIN
    datalake_inspections.inspection_booking AS ib
      ON ib.id_contract = ct.id_contract
  LEFT JOIN
    datalake_ebdb_contract.contract AS ec
      ON ec.id = ct.id_contract
  WHERE
    ct.ts_updated >= '{load_start_date}'
    AND ct.status <> 'CANCELED'
    AND ec.country_code = 'BR'
    AND ib.inspection_type IN ('offboarding', 'verification')
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY ct.id_contract ORDER BY ib.ts_synced DESC) = 1
),
mediations_via_ticket AS (
  SELECT DISTINCT
    id_ticket,
    id_contract,
    CASE
      WHEN tags LIKE '%checkout_wkf_budg_appr_by_ll%'
        AND tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'both_agreed'
      WHEN tags LIKE '%checkout_wkf_budg_appr_by_ll%'
        AND tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'll_agreed'
      WHEN tags LIKE '%checkout_wkf_budg_appr_by_tt%'
        AND tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'tt_agreed'
      WHEN tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%'
        AND tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'both_disagreed_no_answer'
      ELSE NULL
    END AS squad,
    ts_created,
    ts_solved
  FROM
    datalake_zendesk.tickets_current AS tc
  WHERE
    tc.ts_updated >= '{load_start_date}'
    AND tc.group_name = 'Offboarding Reparos [OFF] [POS] [BACK]'
    AND tc.tags NOT LIKE '%ezsend_one%'
    AND tc.tags NOT LIKE '%closed_by_merge%'
    AND COALESCE(custom_fields['Tipo de Cliente [PRE-SAIDA]'], custom_fields['Tipo de Cliente']) LIKE '%proprietário%' --'
    AND custom_fields['Tipo de Demanda'] = 'demanda_pos_saida'
    AND tc.id_ticket NOT IN ('77360746', '77733019', '78024708')
),
mediations_via_terminator AS (
  SELECT DISTINCT
    t.id_contract,
    ts.id_external AS id_ticket,
    CASE
      WHEN tc.tags LIKE '%checkout_wkf_budg_appr_by_ll%'
        AND tc.tags LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'both_agreed'
      WHEN tc.tags LIKE '%checkout_wkf_budg_appr_by_ll%'
        AND tc.tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%' THEN 'll_agreed'
      WHEN tc.tags LIKE '%checkout_wkf_budg_appr_by_tt%'
        AND tc.tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'tt_agreed'
      WHEN tc.tags NOT LIKE '%checkout_wkf_budg_appr_by_tt%'
        AND tc.tags NOT LIKE '%checkout_wkf_budg_appr_by_ll%' THEN 'both_disagreed_no_answer'
      ELSE NULL
    END AS squad,
    ts.ts_created,
    tc.ts_solved
  FROM
    datalake_terminator_clean.termination_task AS ts
  LEFT JOIN
    datalake_terminator_clean.termination AS t
      ON t.id = ts.id_termination
  LEFT JOIN
    datalake_zendesk.tickets_current AS tc
      ON ts.id_external = tc.id_ticket
  WHERE
    ts.ts_updated >= '{load_start_date}'
    AND ts.type = 'TERMINATION_LANDLORD'
    AND tc.tags NOT LIKE '%closed_by_merge%'
    AND tc.group_name = 'Offboarding Reparos [OFF] [POS] [BACK]'
    AND ts.id_external NOT IN ('77360746', '77733019', '78024708')
),
mediations AS (
  SELECT DISTINCT
    t.id_termination,
    t.id_contract,
    COALESCE(mtr.id_ticket, mtk.id_ticket) AS id_ticket,
    COALESCE(mtr.squad, mtk.squad) AS squad,
    COALESCE(mtr.id_ticket, mtk.id_ticket) IS NOT NULL AS has_mediation_ticket,
    CASE
      WHEN t.ts_termination_finished IS NULL THEN NULL
      WHEN t.repairs_absorbed_ac > 0 OR t.total_tentant_repair_ac > 0 THEN TRUE
      ELSE FALSE
    END has_ac_repairs,
    mtr.id_ticket IS NOT NULL AS is_ticket_opened_via_terminator,
    t.dt_inspection,
    t.ts_termination_request,
    t.ts_termination_finished,
    t.ts_termination_updated
  FROM
    terminations AS t
  LEFT JOIN
    mediations_via_terminator AS mtr
      ON mtr.id_contract = t.id_contract
  LEFT JOIN
    mediations_via_ticket AS mtk
      ON mtk.id_contract = t.id_contract
  WHERE
    t.dt_inspection IS NOT NULL
)
SELECT
  id_termination,
  id_contract,
  id_ticket,
  squad,
  has_mediation_ticket,
  has_ac_repairs,
  is_ticket_opened_via_terminator,
  dt_inspection,
  ts_termination_request,
  ts_termination_finished,
  ts_termination_updated
FROM
  mediations
WHERE
  has_ac_repairs IS TRUE
  AND (
    (
      has_mediation_ticket IS TRUE
      AND squad <> 'both_agreed'
    ) OR (
      has_mediation_ticket IS FALSE
      AND squad IS NULL
    )
  )