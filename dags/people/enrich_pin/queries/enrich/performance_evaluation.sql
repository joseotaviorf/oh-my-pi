WITH
ratings_descriptions AS (
    SELECT
        rlb.id_rating_level,
        rlt.rating_description,
        rlb.numeric_rating
    FROM
        datalake_pin_talent_clean.rating_level_base AS rlb
    INNER JOIN
        datalake_pin_talent_clean.rating_level_translation AS rlt
            ON rlt.id_rating_level = rlb.id_rating_level
            AND rlt.language = 'US'
    INNER JOIN
        datalake_pin_talent_clean.rating_model_base AS rmb
            ON rmb.id_rating_model = rlb.id_rating_model
    INNER JOIN
        datalake_pin_talent_clean.rating_model_translation AS rmt
            ON rmt.id_rating_model = rmb.id_rating_model
            AND rmt.language = 'US'
),
latest_evals_per_person AS (
    SELECT
        eval_d.id_evaluation,
        eval_d.id_person,
        eval_d.id_template_definition,
        eval_d.id_template_period,
        eval_d.status_code AS evaluation_status_code,
        eval_d.dt_performance_document_started,
        eval_d.dt_performance_document_ended,
        eval_d.id_review_period
    FROM
        datalake_pin_performance_clean.evaluation AS eval_d
    LEFT JOIN
        datalake_pin_performance_clean.evaluation_step AS eval_s_chk
            ON eval_s_chk.id_evaluation = eval_d.id_evaluation
            AND eval_s_chk.step_code = 'SHRPDOC'
            AND eval_s_chk.step_status <> 'CANCELLED'
    WHERE
        eval_d.status_code <> 'CANCELLED'
        AND eval_s_chk.id_evaluation IS NOT NULL
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY eval_d.id_person ORDER BY eval_d.id_evaluation DESC) = 1
),
eval_section_ratings AS (
    SELECT
        eval_s.id_evaluation,
        eval_r.id_eval_participant,
        eval_r.role_type,
        tmpl_s.description AS section_description,
        eval_r.calculated_rating,
        rtg_desc.rating_description,
        rtg_desc.id_rating_level
    FROM
        datalake_pin_performance_clean.evaluation_section AS eval_s
    INNER JOIN
        datalake_pin_performance_clean.template_section AS tmpl_s
            ON tmpl_s.id_section = eval_s.id_template_section
    LEFT JOIN
        datalake_pin_performance_clean.evaluation_item AS eval_i
            ON eval_i.id_evaluation = eval_s.id_evaluation AND eval_i.id_eval_section = eval_s.id_eval_section
    LEFT JOIN
        datalake_pin_performance_clean.evaluation_rating AS eval_r
            ON eval_r.id_evaluation = eval_i.id_evaluation AND eval_r.id_reference = eval_i.id_eval_item
    LEFT JOIN
        ratings_descriptions AS rtg_desc
            ON rtg_desc.id_rating_level = eval_r.id_performance_rating
    WHERE
        eval_s.section_type_code <> 'QUESTIONNAIRE'
)

SELECT DISTINCT
    emp_main.id_person,
    latest_eval.id_evaluation,
    latest_eval.id_template_definition,
    latest_eval.id_template_period,
    tmpl_def.id_process_flow,
    latest_eval.id_review_period,
    eval_part.id_eval_participant,
    eval_part.id_person AS id_person_evaluator,
    eval_part.id_eval_role AS id_evaluation_role,
    eval_step.id_evaluation_step,
    eval_step.id_person_completed_step,
    task_role.id_process_task_role,
    impact_rtg.id_rating_level AS id_rating_level_impact,
    leadership_rtg.id_rating_level AS id_rating_level_leadership,
    behavior_rtg.id_rating_level AS id_rating_level_behavior,
    emp_main.person_number,
    rev_period_trans.review_period_name,
    tmpl_period_trans.customary_name AS document_template_name,
    latest_eval.evaluation_status_code AS document_status_code,
    rev_period_base.status_code AS review_period_status_code,
    eval_part_hr.full_name AS evaluator_name,
    eval_part.role_type_code AS evaluator_role_code,
    eval_part.participation_status_code AS evaluator_participation_status_code,
    part_status_lkp.meaning AS evaluator_participation_status_meaning,
    eval_step.step_code AS evaluator_step_code,
    eval_step_status_lkp.meaning AS evaluator_step_status_meaning,
    CASE
        WHEN eval_part.role_type_code = 'PARTICIPANT' THEN 'Participant Evaluation'
        ELSE task_role_trans.translated_manager_task_name
    END AS evaluator_step_task_name,
    role_def_trans_peer.name AS peer_role_name,
    impact_rtg.rating_description AS impact_rating_description,
    leadership_rtg.rating_description AS leadership_rating_description,
    behavior_rtg.rating_description AS behavior_rating_description,
    q_ans_detail.free_text_answer_unlimited AS open_feedback,
    task_role.sequence_number AS task_role_sequence_number,
    impact_rtg.calculated_rating AS impact_calculated_rating,
    leadership_rtg.calculated_rating AS leadership_calculated_rating,
    behavior_rtg.calculated_rating AS behavior_calculated_rating,
    latest_eval.dt_performance_document_started,
    latest_eval.dt_performance_document_ended,
    rev_period_base.dt_started AS dt_review_period_started,
    rev_period_base.dt_ended AS dt_review_period_ended,
    eval_step.ts_step_completed AS ts_evaluator_step_completed,
    NOW() AS ts_load
FROM
    datalake_hr_system.employee_ids AS emp_main
INNER JOIN
    latest_evals_per_person AS latest_eval
        ON latest_eval.id_person = emp_main.id_person
INNER JOIN
    datalake_pin_performance_clean.template_definition_base AS tmpl_def
        ON tmpl_def.id_template_definition = latest_eval.id_template_definition
INNER JOIN
    datalake_pin_performance_clean.template_period_translation AS tmpl_period_trans
        ON tmpl_period_trans.id_template_period = latest_eval.id_template_period AND tmpl_period_trans.language = 'US'
INNER JOIN
    datalake_pin_performance_clean.template_definition_translation AS tmpl_def_trans
        ON tmpl_def_trans.id_template_definition = latest_eval.id_template_definition AND tmpl_def_trans.language = 'US'
INNER JOIN
    datalake_pin_talent_clean.review_period_base AS rev_period_base
        ON rev_period_base.id_review_period = latest_eval.id_review_period
INNER JOIN
    datalake_pin_talent_clean.review_period_translation AS rev_period_trans
        ON rev_period_trans.id_review_period = latest_eval.id_review_period AND rev_period_trans.language = 'US'
INNER JOIN
    datalake_pin_performance_clean.evaluation_participant AS eval_part
        ON eval_part.id_evaluation = latest_eval.id_evaluation
INNER JOIN
    datalake_hr_system.employee_ids AS eval_part_hr
        ON eval_part_hr.id_person = eval_part.id_person
LEFT JOIN
    datalake_pin_performance_clean.evaluation_step AS eval_step
        ON eval_step.id_evaluation = eval_part.id_evaluation AND eval_step.id_evaluation_participant = eval_part.id_eval_participant
        AND (
            (eval_part.role_type_code = 'WORKER' AND eval_step.step_code <> 'MNG_PCPN_FEEDBACK') OR
            (eval_part.role_type_code = 'MANAGER' AND eval_step.step_code <> 'WSEVAL') OR
            (eval_part.role_type_code = 'PARTICIPANT')
        )
LEFT JOIN
    datalake_pin_core_clean.foundation_lookup_value AS part_status_lkp
        ON part_status_lkp.lookup_code = eval_part.participation_status_code
        AND part_status_lkp.lookup_type = 'HRA_PARTICIPATION_STATUS'
        AND part_status_lkp.language_code = 'US'
LEFT JOIN
    datalake_pin_core_clean.foundation_lookup_value AS eval_step_status_lkp
        ON eval_step_status_lkp.lookup_code = eval_step.step_status
        AND eval_step_status_lkp.lookup_type = 'HRA_EVAL_STEP_STATUS'
        AND eval_step_status_lkp.language_code = 'US'
LEFT JOIN
    datalake_pin_performance_clean.task_role_base AS task_role
        ON task_role.id_process_flow = tmpl_def.id_process_flow
        AND task_role.task_code = eval_step.step_code
LEFT JOIN
    datalake_pin_performance_clean.task_role_translation AS task_role_trans
        ON task_role_trans.id_process_task_role = task_role.id_process_task_role
        AND task_role_trans.language = 'US'
LEFT JOIN
    datalake_pin_performance_clean.evaluation_role AS eval_role_peer
        ON eval_role_peer.id_evaluation = eval_part.id_evaluation
        AND eval_role_peer.id_evaluation_role = eval_part.id_eval_role
LEFT JOIN
    datalake_pin_performance_clean.template_role AS tmpl_role_peer
        ON tmpl_role_peer.id_template_role = eval_role_peer.id_template_role    
LEFT JOIN
    datalake_pin_performance_clean.role_definition_translation AS role_def_trans_peer
        ON role_def_trans_peer.id_role = tmpl_role_peer.id_role AND role_def_trans_peer.language = 'US'
LEFT JOIN
    eval_section_ratings AS impact_rtg
        ON impact_rtg.id_evaluation = latest_eval.id_evaluation
        AND impact_rtg.id_eval_participant = eval_part.id_eval_participant
        AND impact_rtg.role_type = eval_part.role_type_code
        AND (eval_step.step_code IS NULL OR eval_step.step_code IN ('WSEVAL','MGREVAL'))
        AND impact_rtg.section_description = 
            CASE
                WHEN (UPPER(tmpl_period_trans.customary_name) LIKE '%CEO' AND eval_part.role_type_code = 'MANAGER') THEN 'Impacto - CEO'
                ELSE 'Impacto'
            END
LEFT JOIN
    eval_section_ratings AS leadership_rtg
        ON leadership_rtg.id_evaluation = latest_eval.id_evaluation
        AND leadership_rtg.id_eval_participant = eval_part.id_eval_participant
        AND leadership_rtg.role_type = eval_part.role_type_code
        AND (eval_step.step_code IS NULL OR eval_step.step_code IN ('WSEVAL','MGREVAL'))
        AND leadership_rtg.section_description =
            CASE
                WHEN (UPPER(tmpl_period_trans.customary_name) LIKE '%CEO' AND eval_part.role_type_code = 'MANAGER') THEN 'Liderança - CEO'
                ELSE 'Liderança'
            END
LEFT JOIN
    eval_section_ratings AS behavior_rtg
        ON behavior_rtg.id_evaluation = latest_eval.id_evaluation
        AND behavior_rtg.id_eval_participant = eval_part.id_eval_participant
        AND behavior_rtg.role_type = eval_part.role_type_code
        AND (eval_step.step_code IS NULL OR eval_step.step_code IN ('WSEVAL','MGREVAL'))
        AND behavior_rtg.section_description =
            CASE
                WHEN (UPPER(tmpl_period_trans.customary_name) LIKE '%CEO' AND eval_part.role_type_code = 'MANAGER') THEN 'Comportamento - CEO'
                ELSE 'Comportamento'
            END
LEFT JOIN
    datalake_pin_questionnaires_clean.questionnaire_participant AS q_part_link
        ON q_part_link.id_subject = eval_part.id_evaluation
        AND q_part_link.id_participant = eval_part.id_eval_participant
        AND (eval_step.step_code IS NULL OR eval_step.step_code IN ('WSEVAL','MGREVAL'))
LEFT JOIN
    datalake_pin_questionnaires_clean.questionnaire_response AS q_submission
        ON q_part_link.id_questionnaire_participant = q_submission.id_questionnaire_participant
        AND q_submission.is_latest_attempt
LEFT JOIN
    datalake_pin_questionnaires_clean.question_response AS q_ans_detail
        ON q_submission.id_questionnaire_response = q_ans_detail.id_questionnaire_response