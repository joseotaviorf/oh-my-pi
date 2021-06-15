WITH front_tickets AS (
    SELECT DISTINCT
        ticket_summary.sk_ticket,
        ticket_summary.sk_user,
        ticket_summary.sk_contract_ticket,
        ticket_summary.channel,
        ticket_summary.group_name,
        ticket_summary.ticket_area,
        ticket_summary.rental_process_step,
        CASE
            WHEN ticket_summary.rental_process_step IN ('Onboarding','Ongoing','Offboarding','Relacionamento') THEN 'POS'
            WHEN ticket_summary.rental_process_step LIKE 'Pré-contrato' THEN 'PRE'
        END AS rental_process_group,
        ticket_summary.subject,
        ticket_summary.customer_type_tag,
        ticket_summary.contact_motivation_tag,
        ticket_summary.contact_theme_tag,
        ticket_summary.ts_created_local,
        ticket_summary.ts_solved_local,
        ticket_summary.ts_closed_local,
        MAX(ticket_summary.back_ticket) AS back_ticket,
        ticket_summary.has_department_transfers,
        ticket_summary.has_analyst_transfers,
        ticket_summary.resolution_survey,
        ticket_summary.call_direction
    FROM
        datamarts.ticket_summary
    WHERE
        sk_user > -1 --we are only including identified users
        AND ((ticket_summary.channel = 'call' AND is_answered = 1) OR (ticket_summary.channel = 'chat') OR (ticket_summary.channel = 'email'))
        AND is_automatic_email = 0
        AND is_bot = 0
        AND is_closed_by_merge = 0
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,17,18,19,20
),
user_recontacts AS (
    SELECT DISTINCT
        sk_ticket,
        COALESCE(telefone_principal, cpf, sk_contract_ticket::TEXT, sk_user::TEXT) AS ticket_user,
        CASE
            WHEN DATEDIFF(hour, LAG(ts_created_local, 1) OVER(PARTITION BY ticket_user ORDER BY ts_created_local), ts_created_local) < 168 THEN 1
            ELSE 0
        END AS is_recontact,
        CASE
            WHEN is_recontact = 0 THEN sk_ticket
        END AS main_ticket,
        ts_created_local
    FROM
        front_tickets
    LEFT JOIN 
        public.dim_user
            USING(sk_user)
),
ticket_sessions AS (
    SELECT
        sk_ticket,
        MAX(main_ticket) OVER(PARTITION BY ticket_user ORDER BY ts_created_local ASC ROWS UNBOUNDED PRECEDING) AS ticket_session,
        ticket_user,
        is_recontact,
        ts_created_local
    FROM
        user_recontacts
),
tickets_by_ticket_session AS (
    SELECT
        ticket_session,
        ticket_user,
        COUNT(DISTINCT sk_ticket) AS tickets,
        MIN(ts_created_local) AS ts_created_local
    FROM
        ticket_sessions
    GROUP BY 1, 2
)
SELECT
    tts.ticket_session AS sk_ticket_session,
    ft.sk_user,
    sk_contract_ticket,
    tts.ticket_user AS session_user,
    ft.channel,
    group_name,
    ticket_area,
    rental_process_step,
    rental_process_group,
    subject,
    customer_type_tag,
    contact_motivation_tag,
    contact_theme_tag,
    ft.back_ticket,
    has_department_transfers,
    has_analyst_transfers,
    ft.resolution_survey,
    tts.tickets AS ticket_count,
    CASE
        WHEN ft.channel <> 'chat'
            AND ((tickets > 1)
            OR ft.back_ticket IS NOT NULL
            OR has_department_transfers > 0
            OR has_analyst_transfers > 0
            OR ft.resolution_survey = 0)
        THEN 0
        WHEN ft.channel = 'chat'
            AND ((tickets > 1)
            OR ft.back_ticket IS NOT NULL
            OR has_department_transfers > 0
            OR ft.resolution_survey = 0)
        THEN 0
        ELSE 1
    END AS is_fcr,
    tts.ts_created_local,
    ts_solved_local,
    ts_closed_local
FROM
    tickets_by_ticket_session AS tts
LEFT JOIN
    front_tickets AS ft
        ON ft.sk_ticket = tts.ticket_session
WHERE
    (call_direction = 'inbound' OR call_direction is null)
