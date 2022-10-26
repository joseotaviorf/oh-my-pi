SELECT
    id AS id_contact,
    user_id AS id_user,
    prospect_id AS id_prospect,
    current_agent_id AS id_current_agent,
    unanswered_messages,
    last_message_sent,
    last_message_sent_at AS ts_last_message_sent,
    created_at AS ts_created,
    updated_at AS ts_updated,
    year,
    month,
    day
FROM
    datalake_sales_flow_raw.contact
WHERE
    year = {year}
    AND month = {month}
    AND day = {day}