SELECT
    DISTINCT(tm.sk_ticket),
    tm.sk_user,    
    tm.sk_contract_ticket,
    tm.channel,
    tm.group_name,
    tm.ticket_area,
    tm.rental_process_step,
    CASE
        WHEN rental_process_step IN ('Onboarding','Ongoing','Offboarding','Relacionamento') THEN 'POS'
        WHEN rental_process_step LIKE 'Pré-contrato' THEN 'PRE'
        END AS rental_process_group,
    tm.subject,    
    dt.customer_type_tag,
    dt.contact_motivation_tag,
    dt.contact_theme_tag,
    tm.is_crr,
    tm.is_fcr,
    tm.csat,
    tm.ts_created_local,
    tm.ts_solved_local,
    tm.ts_closed_local
FROM
    datamarts.ticket_summary AS tm
LEFT JOIN
    tickets.dim_ticket AS dt
        USING(sk_ticket)
WHERE
    ((tm.channel LIKE 'call' AND tm.is_answered = 1) OR (tm.channel LIKE 'chat') OR (tm.channel LIKE 'email'))
    AND tm.is_solved > -1
    AND tm.is_automatic_email = 0
    AND tm.is_bot = 0
    AND tm.is_closed_by_merge = 0