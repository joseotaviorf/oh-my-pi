SELECT
    id AS id_contact,
    user_id AS id_user,
    prospect_id AS id_prospect,
    current_agent_id AS id_current_agent,
    rev,
    revtype AS rev_type,
    revend AS rev_end,
    unanswered_messages,
    last_message_sent,
    user_id_mod AS mod_id_user,
    prospect_id_mod AS mod_id_prospect,
    current_agent_id_mod AS mod_id_current_agent,
    unanswered_messages_mod AS mod_unanswered_messages,
    last_message_sent_mod AS mod_last_message_sent,
    last_message_sent_at_mod AS mod_ts_last_message_sent,
    last_message_sent_at AS ts_last_message_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_test_raw.contact_aud