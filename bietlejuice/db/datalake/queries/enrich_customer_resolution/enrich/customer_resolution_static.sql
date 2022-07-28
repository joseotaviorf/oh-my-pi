SELECT
    id_ticket,
    id_user,
    ticket_channel,
    total_tickets,
    team,
    is_fcr,
    ticket_recontact_list,
    ts_started,
    ts_closed,
    YEAR(ts_closed) AS year,
    MONTH(ts_closed) AS month,
    DAY(ts_closed) AS day
FROM
    datalake_customer_resolution.customer_resolution
WHERE
    DATE(ts_closed) = DATE('{year}-{month}-{day}') - INTERVAL '7 days'
