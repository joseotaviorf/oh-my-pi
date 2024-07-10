WITH 
ToF AS (
    SELECT 
        ft.sk_contract AS id_contract,
        dc.rent,
        dc.is_exit_inspection_opted_out,
        DATE(MAX(dt.ts_created)) AS dt_termination_request,
        MAX(dt.dt_termination) AS dt_termination,
        MAX(DATE(dc.ts_analyst_annulment_input)) AS dt_ended_confirmed
    FROM 
        dw_retention.fact_contract_termination AS ft 
    JOIN 
        dw_retention.dim_termination AS dt
            ON dt.sk_termination = ft.sk_termination
    JOIN 
        dw_rent.dim_contract AS dc
            ON dc.sk_contract = ft.sk_contract
    WHERE 
        dc.country_code = 'BR'
        AND dt.dt_termination <= ADD_MONTHS(CURRENT_DATE, 1)
        AND dt.ts_termination_finished IS NULL
        AND dt.status NOT IN ('CANCELED', 'DONE')
    GROUP BY 
        1, 2, 3
),
analise_tsk_aux AS (
    SELECT
        fit.sk_contract,
        fit.sk_task,
        MAX(TIMESTAMPADD(HOUR, -3, dit.ts_start)) AS ts_task_started
    FROM 
        dw_crm.fact_inspection_tasks AS fit
    JOIN 
        dw_crm.dim_inspection_task AS dit
            ON fit.sk_task = dit.sk_task 
            AND fit.sk_contract > 0
    WHERE 
        dit.titles = '[Qualidade de Vistoria - Offboarding]'    
    GROUP BY 
        1, 2
),
analise_tsk AS (
    SELECT 
        sk_contract,
        sk_task,
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
        ROW_NUMBER() OVER (PARTITION BY sk_contract ORDER BY ts_task_started DESC) = 1
),
analysis_contested AS (
    SELECT
        tsk.sk_contract,
        DATE(tsk.ts_task_started) AS dt_task_started,
        ft.sk_ticket,
        dt.ts_created_local,
        minutes_first_reply_time_calendar,
        CASE 
            WHEN CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Conclusão na Análise de Contestação"]') AS STRING) LIKE '%intermediação%' THEN 'Intermediação'
            WHEN CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Conclusão na Análise de Contestação"]') AS STRING) LIKE '%específicos%' THEN 'Reparos especifícos'
            ELSE CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Conclusão na Análise de Contestação"]') AS STRING)
        END AS resolution_notation,
        DATE(ft.ts_solved_local) AS dt_solved,
        dt_max_comm1_an2,
        dt_max_fin_comm_an2,
        dt_max_fin_tsk_an2,
        COALESCE(CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING), CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Tipo de Cliente"]') AS STRING)) AS client_type
    FROM 
        analise_tsk AS tsk
    JOIN 
        dw_tickets.fact_tickets AS ft
            ON tsk.sk_contract = ft.sk_contract
    JOIN 
        dw_tickets.dim_ticket AS dt 
            ON ft.sk_ticket = dt.sk_ticket
    WHERE 
        dt.group_name IN ('Análise de Vistorias II - Reativa [SO] ')
        AND COALESCE(CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING), CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Tipo de Cliente"]') AS STRING)) LIKE '%proprietário%'
        AND dt.tags LIKE '%ticket_ativo%'
        AND dt.tags NOT LIKE '%não_consegue_comentar_no_laudo%'
        AND dt.tags NOT LIKE '%vt_estender_prazo%'
        AND dt.tags NOT LIKE '%prorrogar_comentarios_laudo%'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY IF(ft.ts_solved_local IS NOT NULL, 0, 1) ASC, dt.ts_created_local ASC) = 1
),
intermediation AS (
    SELECT
        ft.sk_contract,
        ft.sk_ticket,
        DATE(ft.ts_solved_local) AS dt_solved,
        DATE(dt.ts_created_local) AS created_date
    FROM 
        dw_tickets.fact_tickets AS ft
    JOIN 
        dw_tickets.dim_ticket AS dt 
            ON ft.sk_ticket = dt.sk_ticket 
    JOIN
        ToF AS to 
            ON to.id_contract = ft.sk_contract   
    WHERE 
        dt.group_name IN ('Offboarding Reparos [OFF] [POS] [BACK]') 
        AND COALESCE(CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Tipo de Cliente [PRE-SAIDA]"]') AS STRING), CAST(GET_JSON_OBJECT(dt.custom_fields, '$["Tipo de Cliente"]') AS STRING)) LIKE '%proprietário%'
        AND dt.tags NOT LIKE '%closed_by_merge%'
        AND dt.ts_created_local > to.dt_termination_request
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY dt.ts_created_local DESC) = 1
),
repairs_analysis AS (
    SELECT
        ft.sk_contract,
        ft.sk_ticket,
        DATE(dt.ts_created_local) AS created_date,
        DATE(ft.ts_solved_local) AS dt_solved
    FROM 
        dw_tickets.fact_tickets AS ft  
    JOIN 
        dw_tickets.dim_ticket AS dt 
            ON ft.sk_ticket = dt.sk_ticket 
    JOIN
        ToF AS to 
            ON to.id_contract = ft.sk_contract     
    WHERE 
        dt.group_name IN ('Análise de reparos [OFF] [POS] [BACK] ') 
        AND dt.status NOT IN ('deleted') 
        AND dt.tags NOT LIKE '%closed_by_merge%' 
        AND dt.tags NOT LIKE '%fechamento_em_massa_19102023%'
        AND dt.ts_created_local > to.dt_termination_request
        AND ft.sk_ticket NOT IN (
                                    67559749,67559785,67559036,67315629,67632524,67578670,
                                    67613882,67562139,67577586,67619607,67558654,67549115,
                                    67558995,67562220,67558702,67580136,67550673,67549581,
                                    67551316,67547746,67550817,67548006,67559280,67549806,
                                    67558037,67558304,67632030,67318645,67619528,67549211,
                                    67318289,67557940,67551383,67558242
                                ) -- tickets wrongly attributed to this inbox
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY ft.sk_contract ORDER BY ft.ts_solved_local DESC) = 1
),
inspections AS (
    SELECT 
        f.sk_contract, 
        f.ts_created, 
        f.sk_inspection, 
        f.ts_inspected
    FROM 
        dw_inspections.fact_inspection AS f
    JOIN 
        dw_inspections.dim_inspection AS d 
            ON f.sk_inspection = d.sk_inspection
    JOIN 
        ToF AS to 
            ON to.id_contract = f.sk_contract
    WHERE 
        d.inspection_type IN ('offboarding','verification')
        AND status NOT IN ('cancelled')
        AND f.ts_created >= to.dt_termination_request
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY f.sk_contract ORDER BY f.ts_created DESC) = 1
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
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND itr.sk_ticket IS NOT NULL AND itr.dt_solved IS NULL THEN 'mediation'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ac.dt_solved IS NOT NULL THEN 'mediation'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ac.sk_ticket IS NOT NULL AND ac.dt_solved IS NULL THEN 'contest_an'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ar.dt_solved IS NOT NULL AND DATEDIFF(CURRENT_DATE, ar.dt_solved) > 10 THEN 'contest_an'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ar.dt_solved IS NOT NULL AND DATEDIFF(CURRENT_DATE, ar.dt_solved) <= 10 AND ac.sk_ticket IS NULL THEN 'landlord_prompt'
            WHEN DATEDIFF(to.dt_termination, CURRENT_DATE) < 0 AND ar.sk_ticket IS NOT NULL AND ar.dt_solved IS NULL THEN 'repair_an'
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
            ON insp.sk_contract = to.id_contract
    LEFT JOIN 
        repairs_analysis AS ar 
            ON ar.sk_contract = to.id_contract
    LEFT JOIN 
        analysis_contested AS ac 
            ON ac.sk_contract = to.id_contract
    LEFT JOIN 
        intermediation AS itr 
            ON itr.sk_contract = to.id_contract
    WHERE 
        to.id_contract NOT IN (
                              657552,566843,649381,566279,605255,617679,605226,591460,618659,
                              576290,557351,649269,601945,593292,669125,675209,673778,674039,
                              647948,573325,589040,584144,661602,613204,613988,652672,612992,
                              615412,338189,612412,578695,671034,619380,673530,587274,570344,
                              674377,616292,643833,674314,665862,556292,572337
                            ) -- REDE and Brokerage Only contracts // Under Operation Team's analysis
),
tb AS (
    SELECT
        id_contract,
        dt_termination_request,
        dt_termination,
        aging,
        class,
        CASE 
            WHEN class IN ('inspection', 'ERC', 'repair_an', 'landlord_prompt', 'contest_an') AND aging <= 15 THEN 0
            WHEN class IN ('inspection', 'ERC', 'repair_an', 'landlord_prompt', 'contest_an') AND aging > 15 THEN 1
            WHEN class IN ('mediation', 'TF') AND aging <= 30 THEN 0
            WHEN class IN ('mediation', 'TF') AND aging > 30 THEN 1
            ELSE NULL
        END overdue_stock,
        CASE 
            WHEN aging > 30 THEN 1
            ELSE 0
        END anomaly
    FROM 
        funnel
    WHERE 
        aging > 0
)
SELECT 
    CURRENT_DATE AS dt_reference_day,
    SUM(overdue_stock) AS qtd_overdue_stock,
    COUNT(overdue_stock) AS qtd_ongoing_terminations,
    ROUND(100.00 * SUM(overdue_stock)/COUNT(overdue_stock), 2) AS percent_overdue_stock
FROM 
    tb