WITH front_tickets AS (
    SELECT
        ft.sk_ticket,
        ft.sk_contract,
        MIN(ft.sk_user) AS sk_user,
        ft.channel,
        last_back_ticket AS back_ticket,
        direction,
        status,        
        ft.has_transfers,
        ft.total_departments,
        ft.is_solved,
        ts_started,
        ts_closed
    FROM
        customer_support.fact_ticket as ft
    LEFT JOIN
        customer_support.dim_channel
            using(sk_channel)
    WHERE
        sk_user > -1
        AND (front_or_back = 'front' OR front_or_back IS NULL)
    GROUP BY 1,2,4,5,6,7,8,9,10,11,12
),
user_recontacts AS (
    SELECT DISTINCT
        sk_ticket,
        COALESCE(sk_user::TEXT,telefone_principal, cpf, sk_contract::TEXT) AS ticket_user,
        CASE
            WHEN DATEDIFF(hour, LAG(ts_started, 1) OVER(PARTITION BY ticket_user ORDER BY ts_started), ts_started) < 168 THEN 1
            ELSE 0
        END AS is_recontact,
        CASE
            WHEN is_recontact = 0 THEN sk_ticket
        END AS main_ticket,
        ts_started
    FROM
        front_tickets
    LEFT JOIN 
        public.dim_user
            USING(sk_user)
),
ticket_sessions AS (
    SELECT
        sk_ticket,
        MAX(main_ticket) OVER(PARTITION BY ticket_user ORDER BY ts_started ASC ROWS UNBOUNDED PRECEDING) AS ticket_session,
        ticket_user,
        is_recontact,
        ts_started
    FROM
        user_recontacts
),
tickets_by_ticket_session AS (
    SELECT
        ticket_session,
        ticket_user,
        COUNT(DISTINCT sk_ticket) AS tickets,
        MIN(ts_started) AS ts_started
    FROM
        ticket_sessions
    GROUP BY 1, 2
),
ticket_recontact_list AS (
    SELECT 
        ticket_session,
        ticket_user,
        LISTAGG(sk_ticket, ',') WITHIN GROUP (ORDER BY sk_ticket) AS ticket_recontact_list
    FROM
        ticket_sessions
	GROUP BY 1,2
)
SELECT
    tts.ticket_session AS sk_ticket,
    tts.ticket_user AS sk_user,
    sk_contract,
    ft.channel,
    ft.back_ticket,
    has_transfers,
    ft.total_departments,
    ft.is_solved,
    tts.tickets AS ticket_count,
    CASE
        WHEN tickets > 1
            OR ft.back_ticket IS NOT NULL
            OR is_solved = False
        THEN FALSE
        ELSE TRUE
    END AS is_fcr,
    trl.ticket_recontact_list,
    ft.ts_started,
    ft.ts_closed
FROM
    tickets_by_ticket_session AS tts
LEFT JOIN
    ticket_recontact_list AS trl
        ON tts.ticket_session = trl.ticket_session
        AND tts.ticket_user = trl.ticket_user
LEFT JOIN
    front_tickets AS ft
        ON ft.sk_ticket = tts.ticket_session
WHERE
    (direction = 'inbound' OR direction IS NULL)
    AND status = 'closed'