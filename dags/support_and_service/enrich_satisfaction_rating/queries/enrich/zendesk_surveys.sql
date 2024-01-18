WITH zendesk_users_contact AS (
    SELECT
        zuc.id_zendesk_user,
        zuc.id_user,
        zuc.email,
        zuc.role
    FROM
        datalake_zendesk_tickets.zendesk_users_contact AS zuc
    WHERE
        DATE(zuc.ts_updated) <= DATE('{year}-{month}-{day}')
    QUALIFY
        zuc.id_user = MAX(zuc.id_user) OVER(PARTITION BY zuc.id_zendesk_user)
)
SELECT DISTINCT
    sr.id AS id_answer,
    tfm.id_contract,
    sr.id_ticket,
    zuc.id_user AS id_respondent,
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
    datalake_zendesk_ticket_funnels.tickets_funnel_metrics AS tfm
        ON tfm.id_ticket = sr.id_ticket
        AND tfm.year <= {year}
        AND tfm.month <= {month}
        AND tfm.day <= {day}
LEFT JOIN
    zendesk_users_contact AS zuc
        ON zuc.id_zendesk_user = tfm.id_zendesk_requester_user
WHERE
    sr.year = {year}
    AND sr.month = {month}
    AND sr.day = {day}
    AND sr.score IN ('good', 'bad')