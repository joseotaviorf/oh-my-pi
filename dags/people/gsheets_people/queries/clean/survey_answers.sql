SELECT
    NULLIF(answer_id, '') AS answer_id,
    NULLIF(survey_invite_id, '') AS survey_invite_id,
    NULLIF(survey, '') AS survey_title,
    NULLIF(email, '') AS email,
    TO_TIMESTAMP(timestamp, 'M/d/yyyy HH:mm:ss') AS ts_answered,
    CAST(NULLIF(how_clear_are_you_on_this_teams_strategic_goals_, '') AS INT) AS score_strategic_goals_clarity,
    CAST(NULLIF(how_clear_is_your_understanding_of_your_role_and_accountabilities_within_the_team__i_e___responsibilities__goals__decision_rights__, '') AS INT) AS score_own_role_clarity,
    CAST(NULLIF(how_clear_is_your_understanding_of_the_roles_and_accountabilities_of_other_members_on_the_team__i_e___responsibilities__goals__decision_rights__, '') AS INT) AS score_others_role_clarity,
    CAST(NULLIF(how_is_the_atmosphere_within_the_team_, '') AS INT) AS score_team_atmosphere,
    CAST(NULLIF(how_do_team_members_currently_work_together_, '') AS INT) AS score_current_teamwork,
    CAST(NULLIF(how_conflicts_within_this_team_are_handled_, '') AS INT) AS score_conflict_handling,
    CAST(NULLIF(how_effective_is_decision_making_within_the_team__i_e___speed__quality__and_clear_process_decision_rights__, '') AS INT) AS score_decision_making_effectiveness,
    CAST(NULLIF(how_effective_are_team_meetings_, '') AS INT) AS score_meeting_effectiveness,
    CAST(NULLIF(how_effectively_does_the_team_operate_as_a_high_performing_team_, '') AS INT) AS score_team_performance,
    NULLIF(what_are_the_top_priorities_for_this_team_, '') AS open_top_priorities,
    NULLIF(what_are_the_challenges_the_team_is_currently_facing__internally_or_externally__to_meet_these_priorities_, '') AS open_team_challenges,
    NULLIF(what_are_the_issues_impacting_openness_, '') AS open_openness_issues,
    NULLIF(how_should_team_members_work_together_for_this_team_to_be_most_effective_, '') AS open_ideal_teamwork,
    NULLIF(what_would_it_take_to_be_a_5_, '') AS open_improvement_to_perfect_score,
    NULLIF(what_adjective_would_you_use_to_describe_this_team_, '') AS open_team_adjective,
    NULLIF(is_there_anything_you_think__team_leader_name__could_do_differently_, '') AS open_leader_feedback,
    NULLIF(any_additional_comments___optional_, '') AS open_additional_comments,
    NOW() AS ts_load
FROM
    datalake_gsheets_people_raw.survey_answers
WHERE
    answer_id IS NOT NULL
    AND answer_id <> ''
