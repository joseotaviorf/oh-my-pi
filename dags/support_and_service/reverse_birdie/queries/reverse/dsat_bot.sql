WITH
filters as (
    SELECT 
        current_date dt_ref, 
         DATE('{load_start_date}') fdom_oya, 
        year(current_date) year_ref
),
dates as (
    SELECT 
        sk_date, 
        date dt_ref
    FROM 
        dw_public.dim_date dd
    WHERE 
        date between (select fdom_oya from filters)  and (select dt_ref from filters)
),
elegibitity as (
  select 
    id_user as sk_user,
    CASE
      WHEN status = 'CALL_IN_APP_V2' THEN 'TEST_CALL_IN_APP_PRE_BOT'
      WHEN status = 'OUTSIDE_CALL_IN_APP_V2' THEN 'TEST_CALL_IN_APP_POST_BOT'
      ELSE status
      END elegibitity,
    CAST(ts_created AS date) as ts_fluxo_triagem
  FROM 
    datalake_help_center_api_clean.call_in_app_eligibility
  WHERE
    status in ('CALL_IN_APP_V2', 'OUTSIDE_CALL_IN_APP_V2')
),
chatbot_sessions as (
    SELECT 
        fsc.sk_session AS feedback_id, 
        CASE WHEN fsc.sk_ticket = -1 THEN NULL ELSE fsc.sk_ticket END AS ticket_id, 
        CASE WHEN fsc.sk_user = -1 THEN NULL ELSE fsc.sk_user END AS author_id,
        dc.channel,
        fsc.is_retention,
        fsc.is_recontact, 
        fsc.is_churn_chat,
        d.dt_ref AS posted_at,
        cfp.satisfaction_score AS rating,
        da.respondent_comments
    FROM 
        dw_customer_support.fact_sessions_chatbot fsc
    JOIN dates d 
      on fsc.sk_started_chat = d.sk_date
    LEFT JOIN dw_customer_support.dim_chatbot dc 
      on fsc.sk_session = dc.sk_session
    LEFT JOIN dw_satisfaction_rating.fact_answer as cfp 
	    on cfp.sk_answer = fsc.sk_answer 
	    and cfp.sk_survey = fsc.sk_survey  
    LEFT JOIN dw_satisfaction_rating.dim_answer as da 
      on da.sk_answer = fsc.sk_answer
    left join elegibitity as e 
      on e.sk_user = cast(fsc.sk_user as STRING) and e.ts_fluxo_triagem <= d.dt_ref
      WHERE cfp.satisfaction_score IS NOT NULL
),
contract_count AS (
  SELECT  
    id_user, 
    COUNT(DISTINCT case when contract_role = 'tenant' then contract_role else contract_role end)  
  FROM datalake_ebdb_contract.contract_person
  GROUP BY 
        1
  HAVING COUNT(DISTINCT case when contract_role = 'tenant' then contract_role else contract_role end)   = 1
),
final as (
  SELECT distinct
    tkt.feedback_id,
    tkt.ticket_id,
    tkt.author_id,
    tkt.channel,
    tkt.is_retention,	
    tkt.is_recontact,
    tkt.is_churn_chat,
    tkt.posted_at,
    tkt.rating,
      CASE WHEN rating = 5 OR rating = 4 THEN 'promoter'
          WHEN rating = 3 THEN 'passive'
          WHEN rating = 2 OR rating = 1 THEN 'detractor' ELSE  CAST(rating AS STRING) -- Convertendo para varchar
    END AS csat_score_category,
    dd.department AS department,
    COALESCE(CASE WHEN contract_count.id_user is null then null
                  WHEN contract.contract_role = 'tenant' or contract.contract_role = 'dweller' THEN 'Inquilino' ELSE contract_role END, 
            CASE WHEN dim.tem_imovel = '1' THEN 'Proprietario' WHEN dim.tem_imovel = '0' THEN 'Inquilino' ELSE NULL END) AS customer_type,
    CONCAT(CAST(feedback_id AS STRING) , '_', CAST(author_id AS STRING)) account_id,
    'DSAT BOT' as nome_campanha,
          TRIM(
                CONCAT_WS(' ', 
                    CASE 
                        WHEN tkt.respondent_comments IS NOT NULL AND tkt.respondent_comments <> '' THEN
                            CASE 
                                WHEN rating IN (2, 1) THEN 'Motivo da minha insatisfação:'
                                WHEN rating IN (3) THEN 'Motivo da minha nota:'
                                WHEN rating IN (5, 4) THEN 'Motivo da minha satisfação:'
                                ELSE '' 
                            END
                        ELSE ''
                    END, CASE WHEN tkt.respondent_comments IS NOT NULL AND tkt.respondent_comments <> '' THEN tkt.respondent_comments ELSE NULL END
                )
            ) AS text
  FROM chatbot_sessions tkt
  LEFT JOIN dw_customer_support.fact_tickets em
    ON tkt.ticket_id = em.sk_ticket 
  LEFT JOIN	dw_customer_support.dim_department dd	
    on em.sk_main_department = dd.sk_department
  LEFT JOIN datalake_ebdb_contract.contract_person contract
    ON contract.id_user = tkt.author_id
  LEFT JOIN contract_count
    ON contract_count.id_user = contract.id_user
  LEFT JOIN dw_public.dim_user dim
    ON tkt.author_id = dim.sk_user
)
SELECT
  nome_campanha AS csat_campanha,
  feedback_id,
  ticket_id,
  author_id,
  channel,
  is_retention,
  is_recontact,
  is_churn_chat,
  date_format(posted_at, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
  rating,
  csat_score_category,
  department,
  CASE WHEN customer_type = 'Inquilino' THEN 'tenant'
            WHEN customer_type = 'Proprietario' THEN 'landlord'
  ELSE  customer_type END AS customer_type,
      account_id || 
      CASE 
          WHEN customer_type IS NOT NULL AND customer_type <> '' THEN '_' || 
              CASE 
                  WHEN customer_type = 'Inquilino' THEN 'tenant'
                  WHEN customer_type = 'Proprietario' THEN 'landlord'
                  ELSE customer_type
              END
          ELSE ''
      END AS account_id
FROM 
  final