SELECT
    id,
    ticket_id AS id_ticket,
    attendant_name,
    attendant_email,
    customer_email,
    customer_name,
    customer_phone,
    group_name,
    bot_answered AS is_bot_answered,
    TIMESTAMP(attended_at) AS ts_attended,
    TIMESTAMP(created_at) AS ts_created,
    TIMESTAMP(ticket_updated_at) AS ts_ticket_updated,
    TIMESTAMP(updated_at) AS ts_updated
FROM
    datalake_chat_fup_test_raw.chats_chat
