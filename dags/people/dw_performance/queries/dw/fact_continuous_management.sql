WITH current_people AS (
    SELECT
        id_person,
        person_number
    FROM
        datalake_pin_core_clean.all_people
    WHERE
        dt_effective_ended >= DATE('4712-12-31')
),
meeting_topics AS (
    SELECT
        id_check_in_meeting,
        COUNT(*) AS topic_count
    FROM
        datalake_pin_performance_clean.discussion_topic
    GROUP BY
        id_check_in_meeting
),
check_in_notes AS (
    SELECT
        dt.id_check_in_meeting,
        COUNT(note.id_note) AS note_count,
        ARRAY_JOIN(COLLECT_LIST(note.note_text), ' | ') AS manager_feedback_text
    FROM
        datalake_pin_performance_clean.discussion_topic AS dt
    INNER JOIN
        datalake_pin_talent_clean.note AS note
            ON (
                (note.object_type = 'ORA_DISCUSSION_TOPIC' AND note.id_object = dt.id_discussion_topic)
                OR (note.context_type = 'ORA_DISCUSSION_TOPIC' AND note.id_context = dt.id_discussion_topic)
            )
    GROUP BY
        dt.id_check_in_meeting
),
questionnaire_answers AS (
    SELECT
        qp.id_subject AS id_check_in_meeting,
        qp.id_participant AS id_person,
        COUNT(qr.id_question_response) AS answer_count,
        ARRAY_JOIN(
            COLLECT_LIST(
                COALESCE(
                    qr.free_text_answer_unlimited,
                    qr.free_text_answer,
                    qr.multiple_choice_answer_list,
                    ''
                )
            ),
            ' | '
        ) AS questionnaire_text
    FROM
        datalake_pin_questionnaires_clean.questionnaire_participant AS qp
    INNER JOIN
        datalake_pin_questionnaires_clean.questionnaire_response AS qresp
            ON qresp.id_questionnaire_participant = qp.id_questionnaire_participant
    INNER JOIN
        datalake_pin_questionnaires_clean.question_response AS qr
            ON qr.id_questionnaire_response = qresp.id_questionnaire_response
    WHERE
        COALESCE(
            qr.free_text_answer_unlimited,
            qr.free_text_answer,
            qr.multiple_choice_answer_list,
            ''
        ) != ''
    GROUP BY
        qp.id_subject,
        qp.id_participant
),
worker_questionnaires AS (
    SELECT
        qa.id_check_in_meeting,
        qa.answer_count,
        qa.questionnaire_text
    FROM
        questionnaire_answers AS qa
    INNER JOIN
        datalake_pin_performance_clean.check_in_meeting AS cim
            ON cim.id_check_in_meeting = qa.id_check_in_meeting
            AND cim.id_worker_person = qa.id_person
),
manager_questionnaires AS (
    SELECT
        qa.id_check_in_meeting,
        qa.answer_count,
        qa.questionnaire_text
    FROM
        questionnaire_answers AS qa
    INNER JOIN
        datalake_pin_performance_clean.check_in_meeting AS cim
            ON cim.id_check_in_meeting = qa.id_check_in_meeting
            AND cim.id_manager_person = qa.id_person
)
SELECT
    MD5(CAST(cim.id_check_in_meeting AS STRING)) AS sk_continuous_management,
    REPLACE(CAST(cim.dt_check_in AS STRING), '-', '') AS sk_check_in_date,
    worker.person_number AS person_number,
    manager.person_number AS manager_person_number,
    rpt.review_period_name,
    CASE cim.id_check_in_template
        WHEN 300000008306046 THEN 'mid_year_checkpoint'
        WHEN 300000116219293 THEN 'mid_year_checkpoint'
        WHEN 300000087654297 THEN 'pdi'
        WHEN 300000008306049 THEN 'one_on_one'
        ELSE 'unknown'
    END AS document_type,
    CASE
        WHEN COALESCE(worker_q.answer_count, 0) > 0
            OR COALESCE(manager_q.answer_count, 0) > 0
            OR COALESCE(notes.note_count, 0) > 0
            OR cim.is_worker_questionnaire_discussed
            OR cim.is_manager_questionnaire_discussed THEN 'filled'
        WHEN COALESCE(topics.topic_count, 0) > 0 THEN 'in_progress'
        ELSE 'not_started'
    END AS checkpoint_status,
    COALESCE(worker_q.questionnaire_text, '') AS worker_questionnaire_text,
    COALESCE(manager_q.questionnaire_text, '') AS manager_questionnaire_text,
    COALESCE(notes.manager_feedback_text, '') AS manager_feedback_text,
    cim.is_worker_questionnaire_discussed,
    cim.is_manager_questionnaire_discussed,
    cim.dt_check_in,
    NOW() AS ts_load
FROM
    datalake_pin_performance_clean.check_in_meeting AS cim
LEFT JOIN
    current_people AS worker
        ON worker.id_person = cim.id_worker_person
LEFT JOIN
    current_people AS manager
        ON manager.id_person = cim.id_manager_person
LEFT JOIN
    datalake_pin_talent_clean.review_period_translation AS rpt
        ON rpt.id_review_period = cim.id_review_period
        AND rpt.language = 'PTB'
LEFT JOIN
    meeting_topics AS topics
        ON topics.id_check_in_meeting = cim.id_check_in_meeting
LEFT JOIN
    check_in_notes AS notes
        ON notes.id_check_in_meeting = cim.id_check_in_meeting
LEFT JOIN
    worker_questionnaires AS worker_q
        ON worker_q.id_check_in_meeting = cim.id_check_in_meeting
LEFT JOIN
    manager_questionnaires AS manager_q
        ON manager_q.id_check_in_meeting = cim.id_check_in_meeting
