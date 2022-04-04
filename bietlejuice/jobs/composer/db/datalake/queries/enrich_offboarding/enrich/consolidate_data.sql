WITH tkt_v2 AS (
    SELECT
        id_contract,
        SUM(num_ticket_satisfied) AS num_ticket_satisfied,
        SUM(num_ticket_neutral) AS num_ticket_neutral,
        SUM(num_ticket_dissatisfied) AS num_ticket_dissatisfied
    FROM
        datalake_offboarding.customer_support
    WHERE
        department = 'Offboarding Reparos [OFF] [POS] [BACK]'
    GROUP BY
        1
),
tkt_off AS (
    SELECT
        id_contract,
        SUM(num_ticket_satisfied) + SUM(num_ticket_neutral) + SUM(num_ticket_dissatisfied) AS num_tickets,
        SUM(num_ticket_satisfied) AS num_ticket_satisfied,
        SUM(num_ticket_neutral) AS num_ticket_neutral,
        SUM(num_ticket_dissatisfied) AS num_ticket_dissatisfied
    FROM
        datalake_offboarding.customer_support
    WHERE
        front_or_back = 'front'
    GROUP BY
        1
),
flow AS (
    SELECT
        ong.id_contract,
        CASE 
            WHEN npt.id_contract IS NOT NULL THEN 'New Repairs'
            WHEN bw.id_contract IS NOT NULL 
                AND bw.department = 'Offboarding [OFF] [POS] [BACK]' 
                AND ong.is_repair_tenant_duty = TRUE 
                AND ong.repair_resolution = 'REIMBURSED_BY_5A' THEN 'New Repairs'
            WHEN bw.id_contract IS NOT NULL
                AND (bw.department = 'Offboarding Reparos [OFF] [POS] [BACK]'
                    OR (bw.department IN ('Offboarding [OFF] [POS] [BACK]',
                            'B2B [POS] [OFF] [BACK]',
                            'Rescisão Prime [Casa Mineira]',
                            'B2B Prime [OFF] [POS] [BACK]')
                        AND 'true' IN (bw.finishing, 
                            bw.agreement_execution, 
                            bw.intermediation_with_parties,
                            bw.budgeting_sent_iq,
                            bw.reanalysis_repairs,
                            bw.repairs_sent_pp,
                            bw.budgeting_sent_pp))
                    OR (bw.department IN ('Offboarding [OFF] [POS] [BACK]',
                        'B2B [POS] [OFF] [BACK]','Rescisão Prime [Casa Mineira]',
                        'B2B Prime [OFF] [POS] [BACK]')
                        AND bw.budget_range IN ('até_750','de_r__750_a_r__1.000',
                            'de_1.000_a_r__2.500',
                            'acima_de_2.500'))
                ) THEN 'V2 Off'
            WHEN bw.id_contract IS NOT NULL 
                AND bw.department = 'Rescisão - Despejo [OFF][POS][BACK]' THEN 'Despejo'
            WHEN ong.ts_analyst_annulment_input IS NOT NULL 
                AND ong.is_repair_tenant_duty = FALSE 
                AND ong.dt_termination >= '2021-09-29' THEN 'V2 Off' 
            ELSE NULL
        END AS flow
    FROM 
        datalake_offboarding.ongoing ong
    LEFT JOIN 
        datalake_offboarding.tickets npt 
            ON npt.id_contract = ong.id_contract
            AND npt.group_name = 'Novo Off - Reparos [POS] [BACK]'
            AND npt.dt_created >= '2021-02-02'
    LEFT JOIN 
        datalake_offboarding.budgeting_window bw
            ON bw.id_contract = ong.id_contract
)
SELECT DISTINCT
    ong.id,
    ong.id_contract,
    ong.id_house,
    flow.flow AS flow,
    ong.repair_resolution,
    CASE
        WHEN bw.budget_range = 'até_750'
            OR bw.budget_range = 'de_r__750_a_r__1.000' THEN 'Ate 1000'
        WHEN bw.budget_range = 'de_1.000_a_r__2.500' THEN 'De 1000 a 2500'
        WHEN bw.budget_range = 'acima_de_2.500' THEN 'Acima de 2500'
        ELSE NULL
    END AS budgeting_window,
    CASE
        WHEN bw.finishing = 'true' THEN 'finalizacao'
        WHEN bw.agreement_execution = 'true' THEN 'execucao_acordo'
        WHEN bw.intermediation_with_parties = 'true' THEN 'intermediacao_com_partes'
        WHEN bw.budgeting_sent_iq = 'true' THEN 'orcamentacao_enviada_iq'
        WHEN bw.budgeting_performed = 'true' THEN 'orcamentacao_realizada'
        WHEN bw.reanalysis_repairs = 'true' THEN 'analise_2'
        WHEN bw.repairs_sent_pp = 'true' THEN 'analise_1'
        WHEN bw.budgeting_sent_pp = 'true' THEN 'analise_1'
        ELSE NULL
    END AS stage_v2,
    CASE
        WHEN bw.tags = 'pp_não_respondeu_v0' THEN 'pp_nao_respondeu'
        WHEN bw.tags = 'pp_concorda_com_apontamentos_v0' THEN 'pp_concorda_com_apontamentos'
        WHEN bw.tags = 'pp_solicita_mais_reparos_indevidos_v0' THEN 'apenas_reparos_indevidos'
        WHEN bw.tags = 'pp_solicita_mais_reparos_devidos_v0' THEN 'pp_solicitou_mais_reparos'
        ELSE bw.tags 
    END AS tags_analysis_2,
    CASE
        WHEN bw.agreement_between_parties = 'acionamento_da_proteção' THEN 'acionamento_da_protecao'
        WHEN bw.agreement_between_parties = 'execução_de_reparos_pelo_5a' THEN 'execucao_de_reparos_pelo_5a'
        WHEN bw.agreement_between_parties = 'execução_de_reparos_pelo_iq' THEN 'execucao_de_reparos_pelo_iq'
        ELSE bw.agreement_between_parties 
    END AS agreement_between_parties,
    CAST(ong.repair_cost AS DECIMAL(20,2)) AS repair_cost,
    CASE
        WHEN ong.ts_termination_finished < ong.dt_termination THEN 0
        WHEN ong.ts_termination_finished >= ong.dt_termination THEN DATEDIFF(ong.ts_termination_finished,ong.dt_termination)
        ELSE NULL
    END AS frt_ldt_greater_than_0,
    CASE
        WHEN ong.ts_termination_finished IS NOT NULL 
            AND ong.dt_termination IS NOT NULL THEN DATEDIFF(ong.ts_termination_finished,ong.dt_termination)
        ELSE NULL
    END AS frt,
    COALESCE(nps_agg.number_of_responses, 0) AS number_of_responses_nps,
    COALESCE(nps_agg.number_of_responses_pp, 0) AS number_of_responses_pp,
    COALESCE(nps_agg.number_of_responses_iq, 0) AS number_of_responses_iq,
    nps_agg.nps_pp AS nps_pp,
    nps_agg.nps_iq AS nps_iq,
    REPLACE(insp_analysis.status,'á','a') AS an_vt1_flag,
    DATEDIFF(ong.dt_termination, COALESCE(ong.dt_contract_entrance, ong.dt_contract_started)) AS contract_lifetime,
    DATEDIFF(ong.dt_last_inspection_synched, ong.dt_termination) AS ldt_td_inspect,
    DATEDIFF(ong.ts_analyst_annulment_input, ong.dt_last_inspection_synched) AS ldt_erc_insp,
    DATEDIFF(ia.dt_completed_date, ong.dt_last_inspection_synched) AS ldt_an_vt2_Insp,  
    DATEDIFF(ong.ts_termination_finished, ia.dt_completed_date) AS ldt_tf_an_vt2,
    DATEDIFF(ong.ts_termination_finished, ong.ts_analyst_annulment_input) AS ldt_erc_tf,
    DATEDIFF(ong.ts_analyst_annulment_input, ong.dt_termination) AS ldt_td_erc,
    DATEDIFF(ia.dt_completed_date, ong.ts_analyst_annulment_input) AS ldt_erc_an_vt_end,
    DATEDIFF(ia.dt_completed_date, ong.dt_termination) AS ldt_td_an_vt2,
    DATEDIFF(ong.dt_termination,NOW()) AS today_td,
    tkt_v2.num_ticket_satisfied AS num_ticket_v2_satisfied,
    tkt_v2.num_ticket_neutral AS num_ticket_v2_neutral,
    tkt_v2.num_ticket_dissatisfied AS num_ticket_v2_dissatisfied,
    tkt_off.num_tickets AS num_ticket_off_front,
    tkt_off.num_ticket_satisfied AS num_ticket_off_front_satisfied,
    tkt_off.num_ticket_neutral AS num_ticket_off_front_neutral,
    tkt_off.num_ticket_dissatisfied AS num_ticket_off_front_dissatisfied,
    bw.interaction_pp AS is_interaction_pp,
    ong.is_b2b,
    ong.is_repair_tenant_duty,
    ong.is_workflow,
    ong.dt_last_inspection_synched AS dt_inspected,
    ia.dt_completed_date AS dt_insp_analysis_completed,
    CASE
        WHEN base_tkt.group_name = 'QualiVisOrça [OFF] [POS] [BACK]'
            AND base_tkt.dt_created >= '2021-01-01' THEN base_tkt.dt_created
        ELSE NULL
    END AS dt_created_budgeting_app,
    CASE
        WHEN base_tkt.group_name = 'QualiVisOrça [OFF] [POS] [BACK]'
            AND base_tkt.dt_created >= '2021-01-01' THEN base_tkt.dt_solved
        ELSE NULL
    END AS dt_solved_budgeting_app,
    CASE
        WHEN base_tkt.group_name = 'Prestadores Parceiros [REP] [POS] [BACK]'
            AND base_tkt.dt_created >= '2021-01-01'
            AND base_tkt.dt_created >= ong.dt_termination THEN base_tkt.dt_created
        ELSE NULL
    END AS dt_created_budgeting,
    CASE
        WHEN base_tkt.group_name = 'Prestadores Parceiros [REP] [POS] [BACK]'
            AND base_tkt.dt_created >= '2021-01-01'
            AND base_tkt.dt_solved >= ong.dt_termination THEN base_tkt.dt_solved
        ELSE NULL
    END AS dt_solved_budgeting,
    CASE 
        WHEN flow.flow = 'New Repairs' 
            AND base_tkt.group_name = 'Novo Off - Reparos [POS] [BACK]'
            AND base_tkt.dt_created >= '2021-02-02' THEN base_tkt.dt_created
        WHEN base_tkt.group_name = 'Proteção QuintoAndar [OFF] [POS] [BACK]'
            AND base_tkt.is_activation_protection THEN base_tkt.dt_created
        ELSE NULL
    END AS dt_ap_start,
    CASE 
        WHEN flow.flow = 'New Repairs' 
            AND base_tkt.group_name = 'Novo Off - Reparos [POS] [BACK]'
            AND base_tkt.dt_created >= '2021-02-02' THEN base_tkt.dt_solved
        WHEN base_tkt.group_name = 'Proteção QuintoAndar [OFF] [POS] [BACK]'
            AND base_tkt.is_activation_protection THEN base_tkt.dt_solved
        ELSE NULL
    END AS dt_ap_solved,
    CASE 
        WHEN ong.ts_analyst_annulment_input >= ong.ts_termination_finished 
            AND ong.ts_analyst_annulment_input >= ia.dt_completed_date THEN ong.ts_analyst_annulment_input
        WHEN ia.dt_completed_date >= ong.ts_termination_finished 
            AND ia.dt_completed_date >= ong.ts_analyst_annulment_input THEN ia.dt_completed_date
        ELSE ong.ts_termination_finished
    END AS dt_tf_v2,
    bw.dt_analysis AS dt_analysis_1,
    bw.dt_reanalysis AS dt_analysis_2,
    bw.dt_budgeted,
    bw.dt_communicated_iq,
    bw.dt_intermediate,
    bw.dt_agreement_executed,
    bw.dt_finished,
    ong.dt_termination,
    insp_analysis.ts_input AS ts_an_vt1,
    ong.ts_termination_request,
    ong.ts_termination_finished,
    ong.ts_analyst_annulment_input AS ts_ended_confirmed,
    ong.ts_created_inspection
FROM 
    datalake_offboarding.ongoing ong
LEFT JOIN 
    datalake_offboarding.inspection_analysis ia 
        ON ia.id_contract = ong.id_contract 
        AND ia.contract_rank = 1
LEFT JOIN
    datalake_offboarding.tickets base_tkt
        ON base_tkt.id_contract = ong.id_contract
LEFT JOIN 
    datalake_offboarding.budgeting_window bw
        ON bw.id_contract = ong.id_contract
LEFT JOIN
    datalake_offboarding.nps_agg
        ON nps_agg.id_contract = ong.id_contract
LEFT JOIN
    datalake_gsheets_clean.inspection_analysis_forms insp_analysis
        ON insp_analysis.id_contract = ong.id_contract
        AND insp_analysis.status NOT IN ('Isento na ferramenta','PP já comentou no laudo')
LEFT JOIN
    tkt_V2
        ON tkt_v2.id_contract = ong.id_contract
LEFT JOIN
    tkt_off
        ON tkt_off.id_contract = ong.id_contract
LEFT JOIN
    flow
        ON flow.id_contract = ong.id_contract
        