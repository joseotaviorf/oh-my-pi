SELECT
    id,
    ticket_id as id_ticket,
    attendant_email,
    timestamp(created_at) as ts_created,
    timestamp(updated_at) as ts_updated,
    attendant_name,
    bot_answered as is_bot_answered,
    customer_email,
    customer_name,
    customer_phone,
    timestamp(attended_at) as ts_attended,
    group_name,
    timestamp(ticket_updated_at) as ts_ticket_updated
FROM datalake_chat_fup_raw.chats_chat