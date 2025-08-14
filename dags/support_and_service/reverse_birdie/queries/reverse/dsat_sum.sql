WITH ranked_tickets AS (
      SELECT 
        faa.sk_analyst, 
        faa.sk_answer, 
        faa.facility_satisfaction,
        faa.time_satisfaction,
        faa.support_satisfaction,
        faa.improvements_suggestions,
        faa.ts_submitted as ts_survey_answer, 
        dd.team,
        da.agent_organization as organization,
        row_number() over (partition by faa.sk_answer order by ft.ts_closed desc) as rn
    FROM
        dw_satisfaction_rating.fact_analyst_answers faa 
    LEFT JOIN dw_customer_support.fact_tickets ft 
        ON ft.sk_last_analyst = faa.sk_analyst
    LEFT JOIN dw_customer_support.dim_ticket dt
        ON CAST(dt.sk_ticket AS VARCHAR(20)) = CAST(ft.sk_ticket AS VARCHAR(20))
    LEFT JOIN datalake_customer_support.csat as csat
        ON CAST(csat.id_ticket AS VARCHAR(20)) = CAST(ft.sk_ticket AS VARCHAR(20))
    LEFT JOIN dw_customer_support.dim_department dd 
        ON dd.sk_department = ft.sk_main_department
    LEFT JOIN dw_customer_support.dim_analyst da
      ON da.sk_analyst = faa.sk_analyst
    WHERE ft.ts_closed < faa.ts_submitted),
main AS (
SELECT 
    sk_analyst, 
    sk_answer, 
    facility_satisfaction,
    time_satisfaction,
    support_satisfaction,
    improvements_suggestions,
    ts_survey_answer, 
    team,
    organization
FROM ranked_tickets
WHERE rn = 1
)
      SELECT 
      sk_analyst AS author_id,  
      sk_answer AS feedback_id, 
      ROUND((facility_satisfaction + COALESCE(time_satisfaction,1) + COALESCE(support_satisfaction,1))/3,2) AS rating,
      ts_survey_answer AS posted_at, 
      team,
      organization AS agent_company,
      'SUM' AS csat_campanha,
      CONCAT_WS(
      ', ',
      CASE
         WHEN facility_satisfaction = 1 THEN 'Satisfação com a facilidade de utilizar o MagicLink: Muito insatisfeito'
        WHEN facility_satisfaction = 2 THEN 'Satisfação com a facilidade de utilizar o MagicLink: Insatisfeito'
        WHEN facility_satisfaction = 3 THEN 'Satisfação com a facilidade de utilizar o MagicLink: Neutro'
        WHEN facility_satisfaction = 4 THEN 'Satisfação com a facilidade de utilizar o MagicLink: Satisfeito'
        WHEN facility_satisfaction = 5 THEN 'Satisfação com a facilidade de utilizar o MagicLink: Muito satisfeito'
      END,
      CASE
        WHEN time_satisfaction = 1 THEN 'Satisfação com o tempo para realizar tarefas no MagicLink: Muito insatisfeito'
        WHEN time_satisfaction = 2 THEN 'Satisfação com o tempo para realizar tarefas no MagicLink: Insatisfeito'
        WHEN time_satisfaction = 3 THEN 'Satisfação com o tempo para realizar tarefas no MagicLink: Neutro'
        WHEN time_satisfaction = 4 THEN 'Satisfação com o tempo para realizar tarefas no MagicLink: Satisfeito'
        WHEN time_satisfaction = 5 THEN 'Satisfação com o tempo para realizar tarefas no MagicLink: Muito satisfeito'
      END,
      CASE
        WHEN support_satisfaction = 1 THEN 'Satisfação com o suporte e informações ao longo do uso do MagicLink: Muito insatisfeito'
        WHEN support_satisfaction = 2 THEN 'Satisfação com o suporte e informações ao longo do uso do MagicLink: Insatisfeito'
        WHEN support_satisfaction = 3 THEN 'Satisfação com o suporte e informações ao longo do uso do MagicLink: Neutro'
        WHEN support_satisfaction = 4 THEN 'Satisfação com o suporte e informações ao longo do uso do MagicLink: Satisfeito'
        WHEN support_satisfaction = 5 THEN 'Satisfação com o suporte e informações ao longo do uso do MagicLink: Muito satisfeito'
      END,
      CASE
        WHEN improvements_suggestions IS NOT NULL THEN 'Comentário: ' || improvements_suggestions
      END) AS text,
      year(posted_at) AS year,
      month(posted_at) AS month,
      day(posted_at) AS day,
      NOW() AS ts_load
      FROM
        main
      WHERE sk_analyst NOT IN 
      ('1aa40921-ed2f-4b6e-b4ca-5ffa51b1d45d',
        '3f7ab256-a509-40fb-a058-3c0b5d36fa07',
        'c30ff4d2-a2ce-4119-a56f-ce7526f77178',
        '8f97df34-4e5e-467a-bdc7-d9e3ab2d8258',
        'c66d7dc1-6de7-489c-add1-5c0f3b72ce95',
        'eecb6e6f-d5c8-41e3-8aca-0e9fa3a15b0d',
        '3767f318-827c-4c5c-a62d-d95634ac8f1c',
        '34844a9f-826e-46d1-8720-46371c348cc4',
        'd1f17f9f-dd81-43ca-b88a-c74f60e22e3e')
      AND facility_satisfaction IS NOT NULL
      AND ts_survey_answer >= DATE('{load_start_date}')
