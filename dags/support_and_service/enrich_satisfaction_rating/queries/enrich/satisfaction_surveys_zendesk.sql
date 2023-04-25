SELECT
    sr.id AS id_answer,
    tfm.id_contract,
    sr.id_ticket,
    sr.id_assignee AS id_respondent,
    zuc.email AS respondent_email,
    zuc.role AS respondent_type,
    "customer support" AS service_type,
    "email" AS service_context,
    "zendesk" AS source_name,
    sr.reason AS improvement_tags,
    CASE
        WHEN sr.score = 'bad' THEN 1
        WHEN sr.score = 'good' THEN 5
        ELSE NULL
    END AS satisfaction_score,
    'satisfaction evaluation' AS score_description,
    sr.ts_created AS ts_submitted,
    sr.year,
    sr.month,
    sr.day
FROM
    datalake_zendesk_tickets_clean.satisfaction_ratings AS sr
LEFT JOIN
    datalake_zendesk_tickets.zendesk_users_contact AS zuc
        ON zuc.id_user = sr.id_assignee
LEFT JOIN
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
        ON tfm.id_ticket = sr.id_ticket
WHERE
    sr.year = {year}
    AND sr.month = {month}
    AND sr.day = {day}