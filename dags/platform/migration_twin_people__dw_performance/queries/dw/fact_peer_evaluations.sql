WITH current_people AS (
    SELECT
        id_person,
        person_number
    FROM
        datalake_pin_core_clean.all_people
    WHERE
        dt_effective_ended >= DATE('9999-12-31')
),
peer_ratings AS (
    SELECT
        er.id_eval_participant,
        er.id_reference,
        rlt.rating_description,
        rlb.numeric_rating
    FROM
        datalake_pin_performance_clean.evaluation_rating AS er
    INNER JOIN
        datalake_pin_talent_clean.rating_level_translation AS rlt
            ON er.id_performance_rating = rlt.id_rating_level
            AND rlt.language = 'US'
    INNER JOIN
        datalake_pin_talent_clean.rating_level_base AS rlb
            ON rlt.id_rating_level = rlb.id_rating_level
    WHERE
        er.reference_type = 'ITEM'
        AND er.role_type = 'PARTICIPANT'
),
base_eval_items AS (
    SELECT
        e.id_evaluation,
        ei.id_eval_item,
        CASE
            WHEN hsdvl.name ILIKE '%Leadership%' THEN 'Leadership'
            WHEN hsdvl.name ILIKE '%Impact%' THEN 'Impact'
            WHEN hsdvl.name ILIKE '%Achieveme%' THEN 'Impact'
            WHEN hsdvl.name ILIKE '%Behavi%' THEN 'Behavior'
        END AS section_name
    FROM
        datalake_pin_performance_clean.evaluation AS e
    INNER JOIN
        datalake_pin_performance_clean.evaluation_section AS es
            ON e.id_evaluation = es.id_evaluation
    INNER JOIN
        datalake_pin_performance_clean.template_section AS hts
            ON es.id_template_section = hts.id_section
    INNER JOIN
        datalake_pin_performance_clean.section_definition_translation AS hsdvl
            ON hts.id_section_definition = hsdvl.id_section_definition
    INNER JOIN
        datalake_pin_performance_clean.evaluation_item AS ei
            ON es.id_eval_section = ei.id_eval_section
    WHERE
        hsdvl.language = 'US'
        AND (
            hsdvl.name ILIKE '%Leadership%'
            OR hsdvl.name ILIKE '%Impact%'
            OR hsdvl.name ILIKE '%Achieveme%'
            OR hsdvl.name ILIKE '%Behavi%'
        )
),
peer_section_ratings AS (
    SELECT
        ep.id_eval_participant,
        MAX(CASE WHEN bei.section_name = 'Impact' THEN pr.rating_description END) AS description_impact,
        MAX(CASE WHEN bei.section_name = 'Behavior' THEN pr.rating_description END) AS description_behavior,
        MAX(CASE WHEN bei.section_name = 'Leadership' THEN pr.rating_description END) AS description_leadership,
        MAX(CASE WHEN bei.section_name = 'Impact' THEN pr.numeric_rating END) AS numeric_impact,
        MAX(CASE WHEN bei.section_name = 'Behavior' THEN pr.numeric_rating END) AS numeric_behavior,
        MAX(CASE WHEN bei.section_name = 'Leadership' THEN pr.numeric_rating END) AS numeric_leadership
    FROM
        datalake_pin_performance_clean.evaluation_participant AS ep
    INNER JOIN
        base_eval_items AS bei
            ON bei.id_evaluation = ep.id_evaluation
    LEFT JOIN
        peer_ratings AS pr
            ON pr.id_eval_participant = ep.id_eval_participant
            AND pr.id_reference = bei.id_eval_item
    WHERE
        ep.role_type_code = 'PARTICIPANT'
    GROUP BY
        ep.id_eval_participant
),
peer_open_text AS (
    SELECT
        ep.id_eval_participant,
        ARRAY_JOIN(
            COLLECT_LIST(
                COALESCE(qr.free_text_answer_unlimited, qr.free_text_answer, '')
            ),
            ' | '
        ) AS open_evaluation
    FROM
        datalake_pin_performance_clean.evaluation_participant AS ep
    INNER JOIN
        datalake_pin_questionnaires_clean.questionnaire_participant AS qp
            ON qp.id_subject = ep.id_evaluation
            AND qp.id_participant = ep.id_eval_participant
    INNER JOIN
        datalake_pin_questionnaires_clean.questionnaire_response AS qresp
            ON qresp.id_questionnaire_participant = qp.id_questionnaire_participant
    INNER JOIN
        datalake_pin_questionnaires_clean.question_response AS qr
            ON qr.id_questionnaire_response = qresp.id_questionnaire_response
    WHERE
        ep.role_type_code = 'PARTICIPANT'
        AND COALESCE(qr.free_text_answer_unlimited, qr.free_text_answer, '') != ''
    GROUP BY
        ep.id_eval_participant
),
participant_context AS (
    SELECT
        ep.id_eval_participant,
        ep.id_person AS id_participant_person,
        e.id_person AS id_evaluated_person,
        COALESCE(CAST(ep.ts_feedback_completed AS DATE), DATE('{load_start_date}')) AS dt_reference
    FROM
        datalake_pin_performance_clean.evaluation_participant AS ep
    INNER JOIN
        datalake_pin_performance_clean.evaluation AS e
            ON e.id_evaluation = ep.id_evaluation
    WHERE
        ep.role_type_code = 'PARTICIPANT'
),
participant_assignment AS (
    SELECT
        pc.id_eval_participant,
        im.id_assignment
    FROM
        participant_context AS pc
    INNER JOIN
        datalake_people.identifier_mapping AS im
            ON im.id_person = pc.id_participant_person
            AND im.is_valid_assignment
            AND im.dt_started IS NOT NULL
            AND pc.dt_reference >= im.dt_started
            AND pc.dt_reference <= COALESCE(im.dt_actual_termination, DATE('9999-12-31'))
),
participant_manager_ranked AS (
    SELECT
        pa.id_eval_participant,
        sup.id_manager,
        ROW_NUMBER() OVER (
            PARTITION BY pa.id_eval_participant
            ORDER BY sup.is_primary DESC, sup.dt_effective_started DESC
        ) AS rn
    FROM
        participant_assignment AS pa
    INNER JOIN
        participant_context AS pc
            ON pc.id_eval_participant = pa.id_eval_participant
    LEFT JOIN
        datalake_pin_core_clean.assignment_supervisor AS sup
            ON sup.id_assignment = pa.id_assignment
            AND sup.manager_type = 'LINE_MANAGER'
            AND pc.dt_reference >= sup.dt_effective_started
            AND pc.dt_reference <= sup.dt_effective_ended
),
participant_manager AS (
    SELECT
        id_eval_participant,
        id_manager AS id_participant_line_manager
    FROM
        participant_manager_ranked
    WHERE
        rn = 1
)
SELECT
    MD5(CAST(ep.id_eval_participant AS STRING)) AS sk_peer_evaluation,
    evaluated.person_number AS person_number,
    peer.person_number AS peer_person_number,
    im.assignment_number,
    rpt.review_period_name AS cycle_name,
    ep.participation_status_code AS participation_status,
    -- Upward leadership feedback uses role_type_code = PARTICIPANT in PIN; classify by
    -- whether the evaluated person was the participant's line manager at feedback completion.
    CASE
        WHEN pc.id_evaluated_person = pm.id_participant_line_manager THEN 'LEADERSHIP'
        ELSE 'PEER'
    END AS participant_role_type,
    psr.description_impact,
    psr.description_behavior,
    psr.description_leadership,
    COALESCE(pot.open_evaluation, '') AS open_evaluation,
    psr.numeric_impact,
    psr.numeric_behavior,
    psr.numeric_leadership,
    ep.ts_feedback_completed,
    NOW() AS ts_load
FROM
    datalake_pin_performance_clean.evaluation_participant AS ep
INNER JOIN
    datalake_pin_performance_clean.evaluation AS e
        ON e.id_evaluation = ep.id_evaluation
INNER JOIN
    datalake_people.identifier_mapping AS im
        ON im.id_assignment = e.id_assignment
LEFT JOIN
    current_people AS evaluated
        ON evaluated.id_person = e.id_person
LEFT JOIN
    current_people AS peer
        ON peer.id_person = ep.id_person
LEFT JOIN
    datalake_pin_talent_clean.review_period_translation AS rpt
        ON rpt.id_review_period = e.id_review_period
        AND rpt.language = 'US'
LEFT JOIN
    peer_section_ratings AS psr
        ON psr.id_eval_participant = ep.id_eval_participant
LEFT JOIN
    peer_open_text AS pot
        ON pot.id_eval_participant = ep.id_eval_participant
INNER JOIN
    participant_context AS pc
        ON pc.id_eval_participant = ep.id_eval_participant
LEFT JOIN
    participant_manager AS pm
        ON pm.id_eval_participant = ep.id_eval_participant
WHERE
    ep.role_type_code = 'PARTICIPANT'
