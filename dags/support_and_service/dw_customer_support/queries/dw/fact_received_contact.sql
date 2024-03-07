WITH received_contact AS (
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
        department,
        COALESCE(id_reservation, '') AS sk_reservation,
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
        channel,
        status,
        completion_reason,
        customer_phone,
        customer_email,
        agent_email,
        average_reply_time,
        total_talk_time,
        total_queue_time,
        total_wrap_up_time,
        total_waiting_time,
        first_reply_time,
        total_handling_time,
        is_answered,
        is_per_team_task,
        ts_reservation_created,
        ts_created
    FROM
        datalake_customer_support.received_demand
)
SELECT
    sk_interaction,
    sk_contact,
    sk_call,
    MD5(department) AS sk_department,
    sk_reservation,
    sk_session,
    sk_task,
    sk_taxonomy,
    sk_ticket,
    sk_user,
    MD5(agent_email) AS sk_agent,
    channel,
    status,
    completion_reason,
    customer_phone,
    customer_email,
    agent_email,
    average_reply_time,
    total_talk_time,
    total_queue_time,
    total_wrap_up_time,
    total_waiting_time,
    first_reply_time,
    total_handling_time,
    LAG(department) OVER(PARTITION BY sk_contact ORDER BY ts_created) AS transferred_from,
    LEAD(department) OVER(PARTITION BY sk_contact ORDER BY ts_created) AS transferred_to,
    is_answered,
    is_per_team_task,
    CASE
        WHEN ROW_NUMBER() OVER(PARTITION BY sk_contact ORDER BY ts_created) = 1 THEN TRUE
        ELSE FALSE
    END AS is_first_interaction,
    CASE
        WHEN ROW_NUMBER() OVER(PARTITION BY sk_contact ORDER BY ts_created DESC) = 1 THEN TRUE
        ELSE FALSE
    END AS is_last_interaction,
    CASE
        WHEN ROW_NUMBER() OVER(PARTITION BY sk_contact, department ORDER BY ts_created) = 1 THEN TRUE
        ELSE FALSE
    END AS is_first_department_interaction,
    ts_reservation_created,
    ts_created
FROM
    received_contact
