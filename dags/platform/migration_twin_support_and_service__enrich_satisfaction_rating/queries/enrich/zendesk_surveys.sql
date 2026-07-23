WITH zendesk_users_contact AS (
    SELECT
        zuc.id_user_zendesk,
        zuc.id_user_main AS id_user,
        zuc.email,
        zuc.role
    FROM
        datalake_support_users.zendesk_users AS zuc
    WHERE
        DATE(zuc.ts_updated) <= DATE('{load_end_date}')
    QUALIFY
        zuc.id_user_main = MAX(zuc.id_user_main) OVER(PARTITION BY zuc.id_user_zendesk)
)
SELECT DISTINCT
    sr.id_satisfaction_rating AS id_answer,
    CAST(tfm.id_contract AS BIGINT) AS id_contract,
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
    {year} AS year,
    {month} AS month,
    {day} AS day
FROM
    datalake_zendesk_clean.satisfaction_ratings AS sr
LEFT JOIN
    datalake_zendesk.tickets_current AS tfm
        ON tfm.id_ticket = sr.id_ticket
LEFT JOIN
    zendesk_users_contact AS zuc
        ON zuc.id_user_zendesk = tfm.id_requester
WHERE
    DATE(sr.ts_updated) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    AND sr.score IN ('good', 'bad')
