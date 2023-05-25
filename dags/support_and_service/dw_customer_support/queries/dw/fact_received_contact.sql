SELECT
    MD5(COALESCE(id_reservation, id_task, id_ticket)) AS sk_interaction,
    MD5(
        COALESCE(
            CONCAT(id_call, 'call'),
            CONCAT(id_session, 'chat'),
            CONCAT(id_ticket, 'email')
        )
    ) AS sk_contact,
    COALESCE(id_call, '') AS sk_call,
    MD5(department) AS sk_department,
    COALESCE(id_session, '') AS sk_session,
    COALESCE(id_task, '') AS sk_task,
    MD5(
        CONCAT(
            COALESCE(step_tag, ''),
            COALESCE(customer_type_tag, ''),
            COALESCE(client_type, ''),
            COALESCE(request_type, ''),
            COALESCE(contact_motivation_tag, ''),
            COALESCE(contact_theme_tag, ''),
            COALESCE(contact_theme_detail_tag, '')
        )
    ) AS sk_taxonomy,
    COALESCE(CAST(id_ticket AS BIGINT), -1) AS sk_ticket,
    COALESCE(id_user, -1) AS sk_user,
    agent_email,
    channel,
    customer_phone,
    customer_email,
    is_answered,
    ts_created,
    ts_updated
FROM
    datalake_customer_support.received_demand
