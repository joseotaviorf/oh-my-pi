WITH flattened AS (
    SELECT
        GET_JSON_OBJECT(payload, '$.user.id') AS id_user,
        NULLIF(
            LOWER(TRIM(GET_JSON_OBJECT(payload, '$.user.email_address'))),
            ''
        ) AS email_user,
        GET_JSON_OBJECT(payload, '$.user.type') AS type_user,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.connectors_used_count') AS BIGINT)
            AS count_chat_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_artifacts_created_count') AS BIGINT)
            AS count_chat_distinct_artifacts_created,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_connectors_used_count') AS BIGINT)
            AS count_chat_distinct_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_conversation_count') AS BIGINT)
            AS count_chat_distinct_conversations,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_files_uploaded_count') AS BIGINT)
            AS count_chat_distinct_files_uploaded,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_projects_created_count') AS BIGINT)
            AS count_chat_distinct_projects_created,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_projects_used_count') AS BIGINT)
            AS count_chat_distinct_projects_used,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_shared_artifacts_viewed_count') AS BIGINT)
            AS count_chat_distinct_shared_artifacts_viewed,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.distinct_skills_used_count') AS BIGINT)
            AS count_chat_distinct_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.message_count') AS BIGINT)
            AS count_chat_messages,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.shared_conversations_viewed_count') AS BIGINT)
            AS count_chat_shared_conversations_viewed,
        CAST(GET_JSON_OBJECT(payload, '$.chat_metrics.thinking_message_count') AS BIGINT)
            AS count_chat_thinking_messages,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.core_metrics.artifacts_created_count') AS BIGINT
        ) AS count_claude_code_artifacts_created,
        CAST(GET_JSON_OBJECT(payload, '$.claude_code_metrics.core_metrics.commit_count') AS BIGINT)
            AS count_claude_code_commits,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.core_metrics.distinct_session_count') AS BIGINT
        ) AS count_claude_code_distinct_sessions,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.core_metrics.lines_of_code.added_count') AS BIGINT
        ) AS count_claude_code_lines_added,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.core_metrics.lines_of_code.removed_count') AS BIGINT
        ) AS count_claude_code_lines_removed,
        CAST(GET_JSON_OBJECT(payload, '$.claude_code_metrics.core_metrics.pull_request_count') AS BIGINT)
            AS count_claude_code_pull_requests,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.edit_tool.accepted_count') AS BIGINT
        ) AS count_claude_code_edit_tool_accepted,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.edit_tool.rejected_count') AS BIGINT
        ) AS count_claude_code_edit_tool_rejected,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.multi_edit_tool.accepted_count') AS BIGINT
        ) AS count_claude_code_multi_edit_tool_accepted,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.multi_edit_tool.rejected_count') AS BIGINT
        ) AS count_claude_code_multi_edit_tool_rejected,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.notebook_edit_tool.accepted_count') AS BIGINT
        ) AS count_claude_code_notebook_edit_tool_accepted,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.notebook_edit_tool.rejected_count') AS BIGINT
        ) AS count_claude_code_notebook_edit_tool_rejected,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.write_tool.accepted_count') AS BIGINT
        ) AS count_claude_code_write_tool_accepted,
        CAST(
            GET_JSON_OBJECT(payload, '$.claude_code_metrics.tool_actions.write_tool.rejected_count') AS BIGINT
        ) AS count_claude_code_write_tool_rejected,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.action_count') AS BIGINT)
            AS count_cowork_actions,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.artifacts_created_count') AS BIGINT)
            AS count_cowork_artifacts_created,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.connectors_used_count') AS BIGINT)
            AS count_cowork_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.dispatch_turn_count') AS BIGINT)
            AS count_cowork_dispatch_turns,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.distinct_connectors_used_count') AS BIGINT)
            AS count_cowork_distinct_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.distinct_plugins_used_count') AS BIGINT)
            AS count_cowork_distinct_plugins_used,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.distinct_session_count') AS BIGINT)
            AS count_cowork_distinct_sessions,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.distinct_skills_used_count') AS BIGINT)
            AS count_cowork_distinct_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.edit_tool_count') AS BIGINT)
            AS count_cowork_edit_tools,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.file_edit_count') AS BIGINT)
            AS count_cowork_file_edits,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.message_count') AS BIGINT)
            AS count_cowork_messages,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.multi_edit_tool_count') AS BIGINT)
            AS count_cowork_multi_edit_tools,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.notebook_edit_tool_count') AS BIGINT)
            AS count_cowork_notebook_edit_tools,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.plugins_used_count') AS BIGINT)
            AS count_cowork_plugins_used,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.sessions_with_file_edits_count') AS BIGINT)
            AS count_cowork_sessions_with_file_edits,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.skills_used_count') AS BIGINT)
            AS count_cowork_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.cowork_metrics.write_tool_count') AS BIGINT)
            AS count_cowork_write_tools,
        CAST(GET_JSON_OBJECT(payload, '$.design_metrics.distinct_projects_created_count') AS BIGINT)
            AS count_design_distinct_projects_created,
        CAST(GET_JSON_OBJECT(payload, '$.design_metrics.distinct_projects_used_count') AS BIGINT)
            AS count_design_distinct_projects_used,
        CAST(GET_JSON_OBJECT(payload, '$.design_metrics.distinct_session_count') AS BIGINT)
            AS count_design_distinct_sessions,
        CAST(GET_JSON_OBJECT(payload, '$.design_metrics.message_count') AS BIGINT)
            AS count_design_messages,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.excel.connectors_used_count') AS BIGINT)
            AS count_office_excel_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.excel.distinct_connectors_used_count') AS BIGINT)
            AS count_office_excel_distinct_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.excel.distinct_session_count') AS BIGINT)
            AS count_office_excel_distinct_sessions,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.excel.distinct_skills_used_count') AS BIGINT)
            AS count_office_excel_distinct_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.excel.message_count') AS BIGINT)
            AS count_office_excel_messages,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.excel.skills_used_count') AS BIGINT)
            AS count_office_excel_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.outlook.connectors_used_count') AS BIGINT)
            AS count_office_outlook_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.outlook.distinct_connectors_used_count') AS BIGINT)
            AS count_office_outlook_distinct_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.outlook.distinct_session_count') AS BIGINT)
            AS count_office_outlook_distinct_sessions,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.outlook.distinct_skills_used_count') AS BIGINT)
            AS count_office_outlook_distinct_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.outlook.message_count') AS BIGINT)
            AS count_office_outlook_messages,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.outlook.skills_used_count') AS BIGINT)
            AS count_office_outlook_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.powerpoint.connectors_used_count') AS BIGINT)
            AS count_office_powerpoint_connectors_used,
        CAST(
            GET_JSON_OBJECT(payload, '$.office_metrics.powerpoint.distinct_connectors_used_count') AS BIGINT
        ) AS count_office_powerpoint_distinct_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.powerpoint.distinct_session_count') AS BIGINT)
            AS count_office_powerpoint_distinct_sessions,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.powerpoint.distinct_skills_used_count') AS BIGINT)
            AS count_office_powerpoint_distinct_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.powerpoint.message_count') AS BIGINT)
            AS count_office_powerpoint_messages,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.powerpoint.skills_used_count') AS BIGINT)
            AS count_office_powerpoint_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.word.connectors_used_count') AS BIGINT)
            AS count_office_word_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.word.distinct_connectors_used_count') AS BIGINT)
            AS count_office_word_distinct_connectors_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.word.distinct_session_count') AS BIGINT)
            AS count_office_word_distinct_sessions,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.word.distinct_skills_used_count') AS BIGINT)
            AS count_office_word_distinct_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.word.message_count') AS BIGINT)
            AS count_office_word_messages,
        CAST(GET_JSON_OBJECT(payload, '$.office_metrics.word.skills_used_count') AS BIGINT)
            AS count_office_word_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.science_metrics.delegation_count') AS BIGINT)
            AS count_science_delegations,
        CAST(GET_JSON_OBJECT(payload, '$.science_metrics.distinct_session_count') AS BIGINT)
            AS count_science_distinct_sessions,
        CAST(GET_JSON_OBJECT(payload, '$.science_metrics.message_count') AS BIGINT)
            AS count_science_messages,
        CAST(GET_JSON_OBJECT(payload, '$.science_metrics.remote_compute_job_count') AS BIGINT)
            AS count_science_remote_compute_jobs,
        CAST(GET_JSON_OBJECT(payload, '$.science_metrics.skills_used_count') AS BIGINT)
            AS count_science_skills_used,
        CAST(GET_JSON_OBJECT(payload, '$.web_search_count') AS BIGINT) AS count_web_searches,
        CAST(GET_JSON_OBJECT(payload, '$.last_activity_date') AS DATE) AS dt_last_activity,
        ts_load,
        year,
        month,
        day
    FROM
        datalake_claude_usage_raw.user_activity
),
ranked AS (
    SELECT
        id_user,
        email_user,
        type_user,
        count_chat_connectors_used,
        count_chat_distinct_artifacts_created,
        count_chat_distinct_connectors_used,
        count_chat_distinct_conversations,
        count_chat_distinct_files_uploaded,
        count_chat_distinct_projects_created,
        count_chat_distinct_projects_used,
        count_chat_distinct_shared_artifacts_viewed,
        count_chat_distinct_skills_used,
        count_chat_messages,
        count_chat_shared_conversations_viewed,
        count_chat_thinking_messages,
        count_claude_code_artifacts_created,
        count_claude_code_commits,
        count_claude_code_distinct_sessions,
        count_claude_code_lines_added,
        count_claude_code_lines_removed,
        count_claude_code_pull_requests,
        count_claude_code_edit_tool_accepted,
        count_claude_code_edit_tool_rejected,
        count_claude_code_multi_edit_tool_accepted,
        count_claude_code_multi_edit_tool_rejected,
        count_claude_code_notebook_edit_tool_accepted,
        count_claude_code_notebook_edit_tool_rejected,
        count_claude_code_write_tool_accepted,
        count_claude_code_write_tool_rejected,
        count_cowork_actions,
        count_cowork_artifacts_created,
        count_cowork_connectors_used,
        count_cowork_dispatch_turns,
        count_cowork_distinct_connectors_used,
        count_cowork_distinct_plugins_used,
        count_cowork_distinct_sessions,
        count_cowork_distinct_skills_used,
        count_cowork_edit_tools,
        count_cowork_file_edits,
        count_cowork_messages,
        count_cowork_multi_edit_tools,
        count_cowork_notebook_edit_tools,
        count_cowork_plugins_used,
        count_cowork_sessions_with_file_edits,
        count_cowork_skills_used,
        count_cowork_write_tools,
        count_design_distinct_projects_created,
        count_design_distinct_projects_used,
        count_design_distinct_sessions,
        count_design_messages,
        count_office_excel_connectors_used,
        count_office_excel_distinct_connectors_used,
        count_office_excel_distinct_sessions,
        count_office_excel_distinct_skills_used,
        count_office_excel_messages,
        count_office_excel_skills_used,
        count_office_outlook_connectors_used,
        count_office_outlook_distinct_connectors_used,
        count_office_outlook_distinct_sessions,
        count_office_outlook_distinct_skills_used,
        count_office_outlook_messages,
        count_office_outlook_skills_used,
        count_office_powerpoint_connectors_used,
        count_office_powerpoint_distinct_connectors_used,
        count_office_powerpoint_distinct_sessions,
        count_office_powerpoint_distinct_skills_used,
        count_office_powerpoint_messages,
        count_office_powerpoint_skills_used,
        count_office_word_connectors_used,
        count_office_word_distinct_connectors_used,
        count_office_word_distinct_sessions,
        count_office_word_distinct_skills_used,
        count_office_word_messages,
        count_office_word_skills_used,
        count_science_delegations,
        count_science_distinct_sessions,
        count_science_messages,
        count_science_remote_compute_jobs,
        count_science_skills_used,
        count_web_searches,
        dt_last_activity,
        ts_load,
        year,
        month,
        day,
        ROW_NUMBER() OVER (
            PARTITION BY
                id_user,
                dt_last_activity
            ORDER BY
                ts_load DESC
        ) AS rn
    FROM
        flattened
)
SELECT
    id_user,
    email_user,
    type_user,
    count_chat_connectors_used,
    count_chat_distinct_artifacts_created,
    count_chat_distinct_connectors_used,
    count_chat_distinct_conversations,
    count_chat_distinct_files_uploaded,
    count_chat_distinct_projects_created,
    count_chat_distinct_projects_used,
    count_chat_distinct_shared_artifacts_viewed,
    count_chat_distinct_skills_used,
    count_chat_messages,
    count_chat_shared_conversations_viewed,
    count_chat_thinking_messages,
    count_claude_code_artifacts_created,
    count_claude_code_commits,
    count_claude_code_distinct_sessions,
    count_claude_code_lines_added,
    count_claude_code_lines_removed,
    count_claude_code_pull_requests,
    count_claude_code_edit_tool_accepted,
    count_claude_code_edit_tool_rejected,
    count_claude_code_multi_edit_tool_accepted,
    count_claude_code_multi_edit_tool_rejected,
    count_claude_code_notebook_edit_tool_accepted,
    count_claude_code_notebook_edit_tool_rejected,
    count_claude_code_write_tool_accepted,
    count_claude_code_write_tool_rejected,
    count_cowork_actions,
    count_cowork_artifacts_created,
    count_cowork_connectors_used,
    count_cowork_dispatch_turns,
    count_cowork_distinct_connectors_used,
    count_cowork_distinct_plugins_used,
    count_cowork_distinct_sessions,
    count_cowork_distinct_skills_used,
    count_cowork_edit_tools,
    count_cowork_file_edits,
    count_cowork_messages,
    count_cowork_multi_edit_tools,
    count_cowork_notebook_edit_tools,
    count_cowork_plugins_used,
    count_cowork_sessions_with_file_edits,
    count_cowork_skills_used,
    count_cowork_write_tools,
    count_design_distinct_projects_created,
    count_design_distinct_projects_used,
    count_design_distinct_sessions,
    count_design_messages,
    count_office_excel_connectors_used,
    count_office_excel_distinct_connectors_used,
    count_office_excel_distinct_sessions,
    count_office_excel_distinct_skills_used,
    count_office_excel_messages,
    count_office_excel_skills_used,
    count_office_outlook_connectors_used,
    count_office_outlook_distinct_connectors_used,
    count_office_outlook_distinct_sessions,
    count_office_outlook_distinct_skills_used,
    count_office_outlook_messages,
    count_office_outlook_skills_used,
    count_office_powerpoint_connectors_used,
    count_office_powerpoint_distinct_connectors_used,
    count_office_powerpoint_distinct_sessions,
    count_office_powerpoint_distinct_skills_used,
    count_office_powerpoint_messages,
    count_office_powerpoint_skills_used,
    count_office_word_connectors_used,
    count_office_word_distinct_connectors_used,
    count_office_word_distinct_sessions,
    count_office_word_distinct_skills_used,
    count_office_word_messages,
    count_office_word_skills_used,
    count_science_delegations,
    count_science_distinct_sessions,
    count_science_messages,
    count_science_remote_compute_jobs,
    count_science_skills_used,
    count_web_searches,
    dt_last_activity,
    ts_load,
    year,
    month,
    day
FROM
    ranked
WHERE
    rn = 1
