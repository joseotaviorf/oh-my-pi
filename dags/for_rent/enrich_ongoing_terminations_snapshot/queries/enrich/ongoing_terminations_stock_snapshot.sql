WITH 
ToF AS (
        SELECT 
        ct.id_contract,
        dc.rent,
        dc.is_exit_inspection_opted_out,
        DATE(MAX(ct.ts_created)) AS dt_termination_request,
        MAX(ct.dt_termination) AS dt_termination,
        MAX(DATE(dc.ts_analyst_annulment_input)) AS dt_ended_confirmed
    FROM 
        datalake_offboarding.contract_termination AS ct
    JOIN 
        datalake_ebdb_contract.contract AS dc
            ON dc.id = ct.id_contract 
    WHERE 
        dc.country_code = 'BR'
        AND ct.dt_termination <= ADD_MONTHS(CURRENT_DATE, 1)
        AND ct.ts_termination_finished IS NULL
        AND ct.status NOT IN ('CANCELED', 'DONE')
    GROUP BY 
        1, 2, 3
),
last_updated_task AS (
  SELECT
      id_task,
      MAX(MAKE_DATE(year, month, day)) AS dt_last_updated
    FROM
      datalake_crm_tasks_flows.tasks_actions_resolutions_flow
    GROUP BY 1
), 
inspection_tasks AS (
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
  FROM
      datalake_crm_tasks_flows.tasks_actions_resolutions_flow AS tarf
  JOIN
      last_updated_task AS lut
          ON tarf.id_task = lut.id_task
          AND MAKE_DATE(tarf.year, tarf.month, tarf.day) = lut.dt_last_updated
  WHERE
      (type IN (
          'AgendarVistoria',
          'AgendarVistoriaPreSaida',
          'AgendarVistoriaSaida',
          'AnalisarPreVistoria',
          'AnaliseVistoriaSaida',
          'CancelarVistoriaPreSaida',
          'ConfirmarVistoriaEntrada',
          'ConfirmarVistoriaPreSaida',
          'ConfirmarVistoriaSaida',
          'EnviarPrimeiroResultadoSaida',
          'EnviarSegundoResultadoSaida',
          'EnviarVistoria',
          'FollowUpVistoriaEntrada',
          'FollowUpVistoriaPreSaida',
          'FollowUpVistoriaSaida',
          'InspectionRescheduled',
          'PrimeiraAnaliseVistoriaSaida',
          'SegundaAnaliseVistoriaSaida'
          )
          OR (id_workgroup IN (
                  'DEP_VISTORIA_ID',
                  'DEP_VISTORIA_LAUDO',
                  'DEP_VISTORIA_OFFBOARDING',
                  'EXIT_INSPECTION_TEAM',
                  'REVISIT_POSTCONTRACT_TEAM'
              )
              AND type = 'Manual')
      )
),
analise_tsk_aux AS (
    SELECT
        COALESCE(ec.id, ib1.id_contract, ib2.id_contract, -1) AS id_contract,
        turf.id_task,
        MAX(TIMESTAMPADD(HOUR, -3, it.ts_start)) AS ts_task_started
    FROM 
        datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf 
    LEFT JOIN
        datalake_ebdb_clean.contract AS ec
            ON turf.origin = 'Contrato'
            AND turf.id_origin = ec.id
    LEFT JOIN
        datalake_inspections.inspection_booking AS ib1
            ON turf.origin = 'Vistoria'
            AND INT(turf.id_origin) IS NOT NULL
            AND turf.id_origin = ib1.id_external
    LEFT JOIN
        datalake_inspections.inspection_booking AS ib2
            ON turf.origin = 'Vistoria'
            AND INT(turf.id_origin) IS NULL
            AND turf.id_origin = ib2.id_client_side
    JOIN 
        inspection_tasks AS it
            ON turf.id_task = it.id_task 
            AND COALESCE(ec.id, ib1.id_contract, ib2.id_contract, -1) > 0
    WHERE
        (
          turf.type IN (
              'AgendarVistoria',
              'AgendarVistoriaPreSaida',
              'AgendarVistoriaSaida',
              'AnalisarPreVistoria',
              'AnaliseVistoriaSaida',
              'CancelarVistoriaPreSaida',
              'ConfirmarVistoriaEntrada',
              'ConfirmarVistoriaPreSaida',
              'ConfirmarVistoriaSaida',
              'EnviarPrimeiroResultadoSaida',
              'EnviarSegundoResultadoSaida',
              'EnviarVistoria',
              'FollowUpVistoriaEntrada',
              'FollowUpVistoriaPreSaida',
              'FollowUpVistoriaSaida',
              'InspectionRescheduled',
              'PrimeiraAnaliseVistoriaSaida',
              'SegundaAnaliseVistoriaSaida'
          )
          OR (
              turf.type = 'Manual'
              AND turf.id_workgroup IN (
                  'DEP_VISTORIA_ID',
                  'DEP_VISTORIA_LAUDO',
                  'DEP_VISTORIA_OFFBOARDING',
                  'EXIT_INSPECTION_TEAM',
                  'REVISIT_POSTCONTRACT_TEAM'
              )
          )
      ) 
      AND 
        it.titles = '[Qualidade de Vistoria - Offboarding]'    
    GROUP BY 
        1, 2
),
analise_tsk AS (
    SELECT 
        id_contract,
        id_task,
        ts_task_started,
        ww_fin_tsk.dt_end_1 AS dt_max_comm1_an2,
        ww_fin_tsk.dt_end_3 AS dt_max_fin_comm_an2,
        ww_fin_tsk.dt_end_4 AS dt_max_fin_tsk_an2
    FROM 
        analise_tsk_aux
    LEFT JOIN 
        datalake_date.workday_window AS ww_fin_tsk 
            ON DATE(ts_task_started) = ww_fin_tsk.dt_ref 
            AND ww_fin_tsk.id_city = 39
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_contract ORDER BY ts_task_started DESC) = 1
),
analysis_contested AS (
    SELECT
        tsk.id_contract,
        DATE(tsk.ts_task_started) AS dt_task_started,
        CAST(tc.id_ticket AS BIGINT) AS id_ticket,
        tc.ts_created - INTERVAL 3 HOUR AS ts_created_local,
        tc.reply_time_min_calendar AS minutes_first_reply_time_calendar,
        CASE 
            WHEN CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Conclusão na Análise de Contestação"]') AS STRING) LIKE '%intermediação%' THEN 'Intermediação'
            WHEN CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Conclusão na Análise de Contestação"]') AS STRING) LIKE '%específicos%' THEN 'Reparos especifícos'
            ELSE CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Conclusão na Análise de Contestação"]') AS STRING)
        END AS resolution_notation,
        DATE(tc.ts_solved - INTERVAL 3 HOUR) AS dt_solved,
        dt_max_comm1_an2,
        dt_max_fin_comm_an2,
        dt_max_fin_tsk_an2,
        COALESCE(CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING), CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente"]') AS STRING)) AS client_type
    FROM 
        analise_tsk AS tsk
    JOIN 
        datalake_zendesk.tickets_current AS tc
            ON tsk.id_contract = COALESCE(CAST(tc.id_contract AS BIGINT), -1)
    WHERE 
        tc.group_name IN ('Análise de Vistorias II - Reativa [SO] ')
        AND COALESCE(CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING), CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente"]') AS STRING)) LIKE '%proprietário%'
        AND tc.tags LIKE '%ticket_ativo%'
        AND tc.tags NOT LIKE '%não_consegue_comentar_no_laudo%'
        AND tc.tags NOT LIKE '%vt_estender_prazo%'
        AND tc.tags NOT LIKE '%prorrogar_comentarios_laudo%'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY tsk.id_contract ORDER BY IF(tc.ts_solved IS NOT NULL, 0, 1) ASC, tc.ts_created ASC) = 1
),
intermediation AS (
    SELECT
        COALESCE(CAST(tc.id_contract AS BIGINT), -1) AS id_contract,
        CAST(tc.id_ticket AS BIGINT) AS id_ticket,
        DATE(tc.ts_solved - INTERVAL 3 HOUR) AS dt_solved,
        DATE(tc.ts_created - INTERVAL 3 HOUR) AS created_date
    FROM 
        datalake_zendesk.tickets_current AS tc
    JOIN
        ToF AS to 
            ON to.id_contract = COALESCE(CAST(tc.id_contract AS BIGINT), -1)
    WHERE 
        tc.group_name IN ('Offboarding Reparos [OFF] [POS] [BACK]') 
        AND COALESCE(CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING), CAST(GET_JSON_OBJECT(TO_JSON(tc.custom_fields), '$["Tipo de Cliente"]') AS STRING)) LIKE '%proprietário%'
        AND tc.tags NOT LIKE '%closed_by_merge%'
        AND (tc.ts_created - INTERVAL 3 HOUR) > to.dt_termination_request
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY tc.id_contract ORDER BY tc.ts_created DESC) = 1
),
repairs_analysis AS (
    SELECT
        COALESCE(CAST(tc.id_contract AS BIGINT), -1) AS id_contract,
        CAST(tc.id_ticket AS BIGINT) AS id_ticket,
        DATE(tc.ts_solved - INTERVAL 3 HOUR) AS dt_solved,
        DATE(tc.ts_created - INTERVAL 3 HOUR) AS created_date
    FROM 
        datalake_zendesk.tickets_current AS tc 
    JOIN
        ToF AS to 
            ON to.id_contract = COALESCE(CAST(tc.id_contract AS BIGINT), -1)    
    WHERE 
        tc.group_name IN ('Análise de reparos [OFF] [POS] [BACK] ') 
        AND tc.status NOT IN ('deleted') 
        AND tc.tags NOT LIKE '%closed_by_merge%' 
        AND tc.tags NOT LIKE '%fechamento_em_massa_19102023%'
        AND (tc.ts_created - INTERVAL 3 HOUR) > to.dt_termination_request
        AND CAST(tc.id_ticket AS BIGINT) NOT IN (
                                    67559749,67559785,67559036,67315629,67632524,67578670,
                                    67613882,67562139,67577586,67619607,67558654,67549115,
                                    67558995,67562220,67558702,67580136,67550673,67549581,
                                    67551316,67547746,67550817,67548006,67559280,67549806,
                                    67558037,67558304,67632030,67318645,67619528,67549211,
                                    67318289,67557940,67551383,67558242
                                ) -- tickets wrongly attributed to this inbox
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY tc.id_contract ORDER BY tc.ts_solved DESC) = 1
),
inspections AS (
    SELECT 
        i.id_contract, 
        i.ts_created, 
        i.id_inspection, 
        i.ts_inspected
    FROM 
        datalake_inspections.inspection_booking AS i
    JOIN 
        ToF AS to 
            ON to.id_contract = i.id_contract
    WHERE 
        i.inspection_type IN ('offboarding','verification')
        AND status NOT IN ('cancelled')
        AND i.ts_created >= to.dt_termination_request
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY i.id_contract ORDER BY i.ts_created DESC) = 1
),
funnel AS (
    SELECT
        to.id_contract,
        to.dt_termination_request,
        to.dt_termination,
        CASE 
            WHEN DATEDIFF(CURRENT_DATE, to.dt_termination) < 0 THEN 0 
            ELSE DATEDIFF(CURRENT_DATE, to.dt_termination) 
        END AS aging,
        CASE 
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND to.is_exit_inspection_opted_out = TRUE AND to.dt_ended_confirmed IS NOT NULL THEN 'TF'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND to.is_exit_inspection_opted_out = TRUE THEN 'ERC'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND itr.dt_solved IS NOT NULL THEN 'TF'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND itr.id_ticket IS NOT NULL AND itr.dt_solved IS NULL THEN 'mediation'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ac.dt_solved IS NOT NULL THEN 'mediation'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ac.id_ticket IS NOT NULL AND ac.dt_solved IS NULL THEN 'contest_an'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ar.dt_solved IS NOT NULL AND DATEDIFF(CURRENT_DATE, ar.dt_solved) > 10 THEN 'contest_an'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ar.dt_solved IS NOT NULL AND DATEDIFF(CURRENT_DATE, ar.dt_solved) <= 10 AND ac.id_ticket IS NULL THEN 'landlord_prompt'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ar.id_ticket IS NOT NULL AND ar.dt_solved IS NULL THEN 'repair_an'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND to.dt_ended_confirmed IS NOT NULL AND insp.ts_inspected IS NOT NULL THEN 'repair_an'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND insp.ts_inspected IS NOT NULL AND to.dt_ended_confirmed IS NULL THEN 'ERC' 
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND insp.ts_inspected IS NULL AND to.dt_ended_confirmed IS NOT NULL THEN 'inspection'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND insp.ts_inspected IS NULL THEN 'inspection'
            ELSE CAST(DATEDIFF(to.dt_termination, CURRENT_DATE) AS STRING)
        END AS class
    FROM 
        ToF AS to 
    LEFT JOIN 
        inspections AS insp 
            ON insp.id_contract = to.id_contract
    LEFT JOIN 
        repairs_analysis AS ar 
            ON ar.id_contract = to.id_contract
    LEFT JOIN 
        analysis_contested AS ac 
            ON ac.id_contract = to.id_contract
    LEFT JOIN 
        intermediation AS itr 
            ON itr.id_contract = to.id_contract
    WHERE 
        to.id_contract NOT IN (
                              657552,566843,649381,566279,605255,617679,605226,591460,618659,
                              576290,557351,649269,601945,593292,669125,675209,673778,674039,
                              647948,573325,589040,584144,661602,613204,613988,652672,612992,
                              615412,338189,612412,578695,671034,619380,673530,587274,570344,
                              674377,616292,643833,674314,665862,556292,572337
                            ) -- REDE and Brokerage Only contracts // Under Operation Team's analysis
)
SELECT
    id_contract,
    dt_termination_request,
    dt_termination,
    aging,
    class,
    IF( 
        (class IN ('inspection', 'ERC', 'repair_an', 'landlord_prompt', 'contest_an') AND aging > 15) 
        OR
        (class IN ('mediation', 'TF') AND aging > 30)
        , TRUE
        , FALSE
    ) AS is_overdue_stock,
    IF(aging > 30, TRUE, FALSE) AS is_anomaly,
    NOW() AS ts_snapshot,
    YEAR(NOW()) AS year,
    MONTH(NOW()) AS month,
    DAY(NOW()) AS day
FROM 
    funnel
WHERE 
    aging > 0