WITH ToF AS (
  SELECT
    ct.id_contract,
    ct.id_termination,
    dc.rent,
    dc.is_exit_inspection_opted_out,
    CAST(MAX(ct.ts_created) AS DATE) AS dt_termination_request,
    MAX(ct.dt_termination) AS dt_termination,
    MAX(CAST(dc.ts_analyst_annulment_input AS DATE)) AS dt_ended_confirmed
  FROM datalake_offboarding.contract_termination AS ct
  JOIN datalake_ebdb_contract.contract AS dc
    ON dc.id = ct.id_contract
  WHERE
    dc.country_code = 'BR'
    AND ct.dt_termination <= ADD_MONTHS(CURRENT_DATE, 1)
    AND ct.ts_termination_finished IS NULL
    AND NOT ct.status IN ('CANCELED', 'DONE')
  GROUP BY
    1,
    2,
    3,
    4
), last_updated_task AS (
  SELECT
    id_task,
    MAX(MAKE_DATE(year, month, day)) AS dt_last_updated
  FROM datalake_crm_tasks_flows.tasks_actions_resolutions_flow
  GROUP BY
    1
), inspection_tasks AS (
  SELECT
    tarf.id_task,
    score_factor,
    version,
    origin,
    type,
    description,
    subject,
    CAST(titles AS STRING) AS titles,
    CAST(workgroups AS STRING) AS workgroups,
    hours_task_started_to_completed AS hours_task_start_to_completed,
    is_resolved AS flg_solved,
    is_task_auto_completed,
    ts_started AS ts_start,
    ts_completed,
    ts_silenced_until,
    NOW() AS ts_load
  FROM datalake_crm_tasks_flows.tasks_actions_resolutions_flow AS tarf
  JOIN last_updated_task AS lut
    ON tarf.id_task = lut.id_task
    AND MAKE_DATE(tarf.year, tarf.month, tarf.day) = lut.dt_last_updated
  WHERE
    (
      type IN ('AgendarVistoria', 'AgendarVistoriaPreSaida', 'AgendarVistoriaSaida', 'AnalisarPreVistoria', 'AnaliseVistoriaSaida', 'CancelarVistoriaPreSaida', 'ConfirmarVistoriaEntrada', 'ConfirmarVistoriaPreSaida', 'ConfirmarVistoriaSaida', 'EnviarPrimeiroResultadoSaida', 'EnviarSegundoResultadoSaida', 'EnviarVistoria', 'FollowUpVistoriaEntrada', 'FollowUpVistoriaPreSaida', 'FollowUpVistoriaSaida', 'InspectionRescheduled', 'PrimeiraAnaliseVistoriaSaida', 'SegundaAnaliseVistoriaSaida')
      OR (
        id_workgroup IN ('DEP_VISTORIA_ID', 'DEP_VISTORIA_LAUDO', 'DEP_VISTORIA_OFFBOARDING', 'EXIT_INSPECTION_TEAM', 'REVISIT_POSTCONTRACT_TEAM')
        AND type = 'Manual'
      )
    )
), analise_tsk_aux AS (
  SELECT
    COALESCE(ec.id, ib1.id_contract, ib2.id_contract, -1) AS id_contract,
    turf.id_task,
    MAX(DATE_ADD(HOUR, -3, it.ts_start)) AS ts_task_started
  FROM datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
  LEFT JOIN datalake_ebdb_clean.contract AS ec
    ON turf.origin = 'Contrato' AND turf.id_origin = ec.id
  LEFT JOIN datalake_inspections.inspection_booking AS ib1
    ON turf.origin = 'Vistoria'
    AND NOT CAST(turf.id_origin AS INT) IS NULL
    AND turf.id_origin = ib1.id_external
  LEFT JOIN datalake_inspections.inspection_booking AS ib2
    ON turf.origin = 'Vistoria'
    AND CAST(turf.id_origin AS INT) IS NULL
    AND turf.id_origin = ib2.id_client_side
  JOIN inspection_tasks AS it
    ON turf.id_task = it.id_task
    AND COALESCE(ec.id, ib1.id_contract, ib2.id_contract, -1) > 0
  WHERE
    (
      turf.type IN ('AgendarVistoria', 'AgendarVistoriaPreSaida', 'AgendarVistoriaSaida', 'AnalisarPreVistoria', 'AnaliseVistoriaSaida', 'CancelarVistoriaPreSaida', 'ConfirmarVistoriaEntrada', 'ConfirmarVistoriaPreSaida', 'ConfirmarVistoriaSaida', 'EnviarPrimeiroResultadoSaida', 'EnviarSegundoResultadoSaida', 'EnviarVistoria', 'FollowUpVistoriaEntrada', 'FollowUpVistoriaPreSaida', 'FollowUpVistoriaSaida', 'InspectionRescheduled', 'PrimeiraAnaliseVistoriaSaida', 'SegundaAnaliseVistoriaSaida')
      OR (
        turf.type = 'Manual'
        AND turf.id_workgroup IN ('DEP_VISTORIA_ID', 'DEP_VISTORIA_LAUDO', 'DEP_VISTORIA_OFFBOARDING', 'EXIT_INSPECTION_TEAM', 'REVISIT_POSTCONTRACT_TEAM')
      )
    )
    AND it.titles = '[Qualidade de Vistoria - Offboarding]'
  GROUP BY
    1,
    2
), analise_tsk AS (
  SELECT
    id_contract,
    id_task,
    ts_task_started,
    dt_max_comm1_an2,
    dt_max_fin_comm_an2,
    dt_max_fin_tsk_an2
  FROM (
    SELECT
      id_contract,
      id_task,
      ts_task_started,
      ww_fin_tsk.dt_end_1 AS dt_max_comm1_an2,
      ww_fin_tsk.dt_end_3 AS dt_max_fin_comm_an2,
      ww_fin_tsk.dt_end_4 AS dt_max_fin_tsk_an2,
      ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY ts_task_started DESC) AS _w
    FROM analise_tsk_aux
    LEFT JOIN datalake_date.workday_window AS ww_fin_tsk
      ON CAST(ts_task_started AS DATE) = ww_fin_tsk.dt_ref AND ww_fin_tsk.id_city = 39
  ) AS _t
  WHERE
    _w = 1
), analysis_contested AS (
  SELECT
    id_contract,
    dt_task_started,
    id_ticket,
    ts_created_local,
    minutes_first_reply_time_calendar,
    resolution_notation,
    dt_solved,
    dt_max_comm1_an2,
    dt_max_fin_comm_an2,
    dt_max_fin_tsk_an2,
    client_type
  FROM (
    SELECT
      tsk.id_contract,
      CAST(tsk.ts_task_started AS DATE) AS dt_task_started,
      CAST(tc.id_ticket AS BIGINT) AS id_ticket,
      tc.ts_created - INTERVAL '3' HOUR AS ts_created_local,
      tc.reply_time_min_calendar AS minutes_first_reply_time_calendar,
      CASE
        WHEN CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Conclusão na Análise de Contestação"]') AS STRING) LIKE '%intermediação%'
        THEN 'Intermediação'
        WHEN CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Conclusão na Análise de Contestação"]') AS STRING) LIKE '%específicos%'
        THEN 'Reparos especifícos'
        ELSE CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Conclusão na Análise de Contestação"]') AS STRING)
      END AS resolution_notation,
      CAST(tc.ts_solved - INTERVAL '3' HOUR AS DATE) AS dt_solved,
      dt_max_comm1_an2,
      dt_max_fin_comm_an2,
      dt_max_fin_tsk_an2,
      COALESCE(
        CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING),
        CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente"]') AS STRING)
      ) AS client_type,
      ROW_NUMBER() OVER (PARTITION BY tsk.id_contract ORDER BY IF(NOT tc.ts_solved IS NULL, 0, 1) ASC, tc.ts_created ASC) AS _w,
      tc.ts_created,
      tc.ts_solved
    FROM analise_tsk AS tsk
    JOIN datalake_zendesk.tickets_current AS tc
      ON tsk.id_contract = COALESCE(CAST(tc.id_contract AS BIGINT), -1)
    WHERE
      tc.group_name IN ('Análise de Vistorias II - Reativa [SO] ')
      AND COALESCE(
        CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING),
        CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente"]') AS STRING)
      ) LIKE '%proprietário%'
      AND tc.tags LIKE '%ticket_ativo%'
      AND NOT tc.tags LIKE '%não_consegue_comentar_no_laudo%'
      AND NOT tc.tags LIKE '%vt_estender_prazo%'
      AND NOT tc.tags LIKE '%prorrogar_comentarios_laudo%'
  ) AS _t
  WHERE
    _w = 1
), intermediation AS (
  SELECT
    id_contract,
    id_ticket,
    dt_solved,
    created_date
  FROM (
    SELECT
      COALESCE(CAST(tc.id_contract AS BIGINT), -1) AS id_contract,
      CAST(tc.id_ticket AS BIGINT) AS id_ticket,
      CAST(tc.ts_solved - INTERVAL '3' HOUR AS DATE) AS dt_solved,
      CAST(tc.ts_created - INTERVAL '3' HOUR AS DATE) AS created_date,
      ROW_NUMBER() OVER (PARTITION BY COALESCE(CAST(tc.id_contract AS BIGINT), -1) ORDER BY tc.ts_created DESC) AS _w,
      tc.ts_created
    FROM datalake_zendesk.tickets_current AS tc
    JOIN ToF AS to
      ON to.id_contract = COALESCE(CAST(tc.id_contract AS BIGINT), -1)
    WHERE
      tc.group_name IN ('Offboarding Reparos [OFF] [POS] [BACK]')
      AND COALESCE(
        CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING),
        CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente"]') AS STRING)
      ) LIKE '%proprietário%'
      AND NOT tc.tags LIKE '%closed_by_merge%'
      AND (
        tc.ts_created - INTERVAL '3' HOUR
      ) > to.dt_termination_request
  ) AS _t
  WHERE
    _w = 1
), repairs_analysis AS (
  SELECT
    id_contract,
    id_ticket,
    dt_solved,
    created_date
  FROM (
    SELECT
      COALESCE(CAST(tc.id_contract AS BIGINT), -1) AS id_contract,
      CAST(tc.id_ticket AS BIGINT) AS id_ticket,
      CAST(tc.ts_solved - INTERVAL '3' HOUR AS DATE) AS dt_solved,
      CAST(tc.ts_created - INTERVAL '3' HOUR AS DATE) AS created_date,
      ROW_NUMBER() OVER (PARTITION BY COALESCE(CAST(tc.id_contract AS BIGINT), -1) ORDER BY tc.ts_solved DESC) AS _w,
      tc.ts_solved
    FROM datalake_zendesk.tickets_current AS tc
    JOIN ToF AS to
      ON to.id_contract = COALESCE(CAST(tc.id_contract AS BIGINT), -1)
    WHERE
      tc.group_name IN ('Análise de reparos [OFF] [POS] [BACK] ')
      AND NOT tc.status IN ('deleted')
      AND NOT tc.tags LIKE '%closed_by_merge%'
      AND NOT tc.tags LIKE '%fechamento_em_massa_19102023%'
      AND (
        tc.ts_created - INTERVAL '3' HOUR
      ) > to.dt_termination_request
      AND NOT CAST(tc.id_ticket AS BIGINT) IN (67559749, 67559785, 67559036, 67315629, 67632524, 67578670, 67613882, 67562139, 67577586, 67619607, 67558654, 67549115, 67558995, 67562220, 67558702, 67580136, 67550673, 67549581, 67551316, 67547746, 67550817, 67548006, 67559280, 67549806, 67558037, 67558304, 67632030, 67318645, 67619528, 67549211, 67318289, 67557940, 67551383, 67558242) /* tickets wrongly attributed to this inbox */
  ) AS _t
  WHERE
    _w = 1
), inspections AS (
  SELECT
    id_contract,
    ts_created,
    id_inspection,
    ts_inspected
  FROM (
    SELECT
      i.id_contract,
      i.ts_created,
      i.id_inspection,
      i.ts_inspected,
      ROW_NUMBER() OVER (PARTITION BY i.id_contract ORDER BY i.ts_created DESC) AS _w
    FROM datalake_inspections.inspection_booking AS i
    JOIN ToF AS to
      ON to.id_contract = i.id_contract
    WHERE
      i.inspection_type IN ('offboarding', 'verification')
      AND NOT status IN ('cancelled')
      AND i.ts_created >= to.dt_termination_request
  ) AS _t
  WHERE
    _w = 1
), funnel AS (
  SELECT
    to.id_contract,
    to.id_termination,
    to.dt_termination_request,
    to.dt_termination,
    CASE
      WHEN DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(to.dt_termination)) < 0
      THEN 0
      ELSE DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(to.dt_termination))
    END AS aging,
    CASE
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND to.is_exit_inspection_opted_out = TRUE
      AND NOT to.dt_ended_confirmed IS NULL
      THEN 'TF'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND to.is_exit_inspection_opted_out = TRUE
      THEN 'ERC'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT itr.dt_solved IS NULL
      THEN 'TF'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT itr.id_ticket IS NULL
      AND itr.dt_solved IS NULL
      THEN 'mediation'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT ac.dt_solved IS NULL
      THEN 'mediation'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT ac.id_ticket IS NULL
      AND ac.dt_solved IS NULL
      THEN 'contest_an'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT ar.dt_solved IS NULL
      AND DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(ar.dt_solved)) > 10
      THEN 'contest_an'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT ar.dt_solved IS NULL
      AND DATEDIFF(TO_DATE(CURRENT_DATE), TO_DATE(ar.dt_solved)) <= 10
      AND ac.id_ticket IS NULL
      THEN 'landlord_prompt'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT ar.id_ticket IS NULL
      AND ar.dt_solved IS NULL
      THEN 'repair_an'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT to.dt_ended_confirmed IS NULL
      AND NOT insp.ts_inspected IS NULL
      THEN 'repair_an'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND NOT insp.ts_inspected IS NULL
      AND to.dt_ended_confirmed IS NULL
      THEN 'ERC'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND insp.ts_inspected IS NULL
      AND NOT to.dt_ended_confirmed IS NULL
      THEN 'inspection'
      WHEN DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) < 0
      AND insp.ts_inspected IS NULL
      THEN 'inspection'
      ELSE CAST(DATEDIFF(TO_DATE(to.dt_termination), TO_DATE(CURRENT_DATE)) AS STRING)
    END AS class
  FROM ToF AS to
  LEFT JOIN inspections AS insp
    ON insp.id_contract = to.id_contract
  LEFT JOIN repairs_analysis AS ar
    ON ar.id_contract = to.id_contract
  LEFT JOIN analysis_contested AS ac
    ON ac.id_contract = to.id_contract
  LEFT JOIN intermediation AS itr
    ON itr.id_contract = to.id_contract
  WHERE
    NOT to.id_contract IN (657552, 566843, 649381, 566279, 605255, 617679, 605226, 591460, 618659, 576290, 557351, 649269, 601945, 593292, 669125, 675209, 673778, 674039, 647948, 573325, 589040, 584144, 661602, 613204, 613988, 652672, 612992, 615412, 338189, 612412, 578695, 671034, 619380, 673530, 587274, 570344, 674377, 616292, 643833, 674314, 665862, 556292, 572337) /* REDE and Brokerage Only contracts // Under Operation Team's analysis */
)
SELECT
  id_contract,
  id_termination,
  dt_termination_request,
  dt_termination,
  aging,
  class,
  IF(
    (
      class IN ('inspection', 'ERC', 'repair_an', 'landlord_prompt', 'contest_an')
      AND aging > 15
    )
    OR (
      class IN ('mediation', 'TF') AND aging > 30
    ),
    TRUE,
    FALSE
  ) AS is_overdue_stock,
  IF(aging > 30, TRUE, FALSE) AS is_anomaly,
  NOW() AS ts_snapshot,
  YEAR(TO_DATE(NOW())) AS year,
  MONTH(TO_DATE(NOW())) AS month,
  DAY(TO_DATE(NOW())) AS day
FROM funnel
WHERE
  aging > 0