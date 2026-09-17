-- One row per closed Teva survey run; inputs for enrich_people_ai LiteLLM jobs.
WITH reference_guide AS (
    SELECT
        CONCAT_WS(
            '\n',
            COLLECT_LIST(
                CONCAT(
                    '- "',
                    phrase,
                    '" (Sentiment: ',
                    sentiment,
                    ') implies context for ',
                    pillar
                )
            )
        ) AS reference_guide_text
    FROM
        datalake_gsheets_people_clean.few_shot_phrases
),
closed_surveys AS (
    SELECT
        survey_invite_id,
        survey_title,
        requester_email,
        answered_count
    FROM
        datalake_gsheets_people_clean.questionnaire_requests
    WHERE
        survey_status = 'Completed'
        AND answered_count > 0
),
aggregated_answers AS (
    SELECT
        survey_invite_id,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_strategic_goals_clarity > 0
                        THEN CAST(score_strategic_goals_clarity AS STRING)
                END
            )
        ) AS strategic_goals_clarity_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_own_role_clarity > 0
                        THEN CAST(score_own_role_clarity AS STRING)
                END
            )
        ) AS own_role_clarity_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_others_role_clarity > 0
                        THEN CAST(score_others_role_clarity AS STRING)
                END
            )
        ) AS others_role_clarity_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_current_teamwork > 0
                        THEN CAST(score_current_teamwork AS STRING)
                END
            )
        ) AS current_teamwork_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_decision_making_effectiveness > 0
                        THEN CAST(score_decision_making_effectiveness AS STRING)
                END
            )
        ) AS decision_making_effectiveness_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_meeting_effectiveness > 0
                        THEN CAST(score_meeting_effectiveness AS STRING)
                END
            )
        ) AS meeting_effectiveness_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_team_performance > 0
                        THEN CAST(score_team_performance AS STRING)
                END
            )
        ) AS team_performance_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_team_atmosphere > 0
                        THEN CAST(score_team_atmosphere AS STRING)
                END
            )
        ) AS team_atmosphere_scores,
        CONCAT_WS(
            ',',
            COLLECT_LIST(
                CASE
                    WHEN score_conflict_handling > 0
                        THEN CAST(score_conflict_handling AS STRING)
                END
            )
        ) AS conflict_handling_scores,
        CONCAT_WS(' | ', COLLECT_LIST(NULLIF(open_top_priorities, ''))) AS top_priorities_answers,
        CONCAT_WS(' | ', COLLECT_LIST(NULLIF(open_team_challenges, ''))) AS team_challenges_answers,
        CONCAT_WS(' | ', COLLECT_LIST(NULLIF(open_ideal_teamwork, ''))) AS ideal_teamwork_answers,
        CONCAT_WS(
            ' | ',
            COLLECT_LIST(NULLIF(open_improvement_to_perfect_score, ''))
        ) AS improvement_to_perfect_score_answers,
        CONCAT_WS(' | ', COLLECT_LIST(NULLIF(open_openness_issues, ''))) AS openness_issues_answers,
        CONCAT_WS(' | ', COLLECT_LIST(NULLIF(open_team_adjective, ''))) AS team_adjective_answers,
        CONCAT_WS(' | ', COLLECT_LIST(NULLIF(open_leader_feedback, ''))) AS leader_feedback_answers,
        CONCAT_WS(' | ', COLLECT_LIST(NULLIF(open_additional_comments, ''))) AS additional_comments_answers
    FROM
        datalake_gsheets_people_clean.survey_answers
    GROUP BY
        survey_invite_id
)
SELECT
    closed_surveys.survey_invite_id,
    closed_surveys.survey_title,
    closed_surveys.requester_email,
    closed_surveys.answered_count,
    aggregated_answers.strategic_goals_clarity_scores,
    aggregated_answers.own_role_clarity_scores,
    aggregated_answers.others_role_clarity_scores,
    aggregated_answers.current_teamwork_scores,
    aggregated_answers.decision_making_effectiveness_scores,
    aggregated_answers.meeting_effectiveness_scores,
    aggregated_answers.team_performance_scores,
    aggregated_answers.team_atmosphere_scores,
    aggregated_answers.conflict_handling_scores,
    aggregated_answers.top_priorities_answers,
    aggregated_answers.team_challenges_answers,
    aggregated_answers.ideal_teamwork_answers,
    aggregated_answers.improvement_to_perfect_score_answers,
    aggregated_answers.openness_issues_answers,
    aggregated_answers.team_adjective_answers,
    aggregated_answers.leader_feedback_answers,
    aggregated_answers.additional_comments_answers,
    reference_guide.reference_guide_text
FROM
    closed_surveys
INNER JOIN
    aggregated_answers
        ON aggregated_answers.survey_invite_id = closed_surveys.survey_invite_id
CROSS JOIN
    reference_guide
