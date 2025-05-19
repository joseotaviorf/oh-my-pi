WITH
ranked_contracts AS (
    SELECT
        sk_contract,
        count(distinct sk_user) 
    FROM dw_rent.fact_contract_people
    where 
        is_contract_user
    group by 1
    having count(distinct sk_user) = 1
), fact_contract_people AS (
SELECT
  p.*
FROM dw_rent.fact_contract_people p
INNER JOIN ranked_contracts 
  ON ranked_contracts.sk_contract = p.sk_contract
WHERE p.is_contract_user
QUALIFY 
  ROW_NUMBER() OVER (PARTITION BY sk_user ORDER BY p.sk_contract desc) = 1
), dados_tickets AS (
  SELECT
    DISTINCT em.id_ticket,
    tkt.sk_contract,
    em.id_user,
    an.email as agent_email,
    an.agent_organization as agent_company,
    COALESCE(em.department, dd.department) AS department,
    date(em.ts_ticket_started) as date_started,
    tkt.sk_sale_offer as offer_id,
    dt.customer_type_tag AS customer_type
  FROM datalake_customer_support.email em
  LEFT JOIN dw_customer_support.fact_tickets tkt 
        ON CAST(em.id_ticket AS BIGINT) = tkt.sk_ticket
    LEFT JOIN dw_customer_support.dim_taxonomy AS dt 
        ON dt.sk_taxonomy = tkt.sk_taxonomy 
    LEFT JOIN dw_customer_support.dim_analyst an 
        ON tkt.sk_first_analyst = an.sk_analyst
    LEFT JOIN fact_contract_people p 
        ON em.id_user = p.sk_user 
        AND is_contract_user
    LEFT JOIN dw_customer_support.dim_department dd	
        ON tkt.sk_main_department = dd.sk_department
),
base_respostas as (
  SELECT 
    sq.id_survey,
    DATE(rc.ts_collected) AS posted_at,
    CASE WHEN sq.id_survey = 'e8f1a7a60f12ba1b' THEN 'CX Padrão' --OK
         WHEN sq.id_survey = '26a5ad040f5a9209' THEN 'Serfin' --OK
         WHEN sq.id_survey = '6ef779f88ac6e1d9' THEN 'Serfin_gatilho' --OK
         WHEN sq.id_survey = '7c875afca4130e7a' THEN 'Quintocred atendimento' --OK
         WHEN sq.id_survey = '12de0eedb5d98a27' THEN 'Collection' --OK
         WHEN sq.id_survey = 'f57ee5802b058791' THEN 'Chaves Offb' --OK
         WHEN sq.id_survey = '34475b9efa7501d9' THEN 'Chaves Onb' --OK
         WHEN sq.id_survey = '29d847ff4d17cc18' THEN 'Vistoria entrada' --OK
         WHEN sq.id_survey = 'f28163ea321f7cab' THEN 'Reparos Ong' --OK
         WHEN sq.id_survey = 'd52aad2976aab0d4' THEN 'Budget Approval' --OK
         WHEN sq.id_survey = 'ccecd6dbe925b337' THEN 'Vistoria entrada' --OK
         WHEN sq.id_survey = '9d64bf0e2f6faa48' THEN 'Vistoria saída' -- OK
         WHEN sq.id_survey = '84b8d08f88b16765' THEN 'Mediação'-- OK
         WHEN sq.id_survey = '7299d5b4e48d041a' THEN 'PP Multi'--OK
         WHEN sq.id_survey = '4a2c89e54ea6c688' THEN 'QuintoCred [inadimplencia/acionamento]' -- OK
         WHEN sq.id_survey = '20d6adebf70801b8' THEN 'Pagamentos' -- OK
         WHEN sq.id_survey = '076f28a3e36bdb87' THEN 'Budget Approval' -- OK
         WHEN sq.id_survey = '00f46ff66c2ff389' THEN 'Vistoria saída' -- OK
    ELSE sq.survey_name END AS survey_name,
    sr.id_response AS message_id,
    sr.response_url,
        SUBSTRING(
    sr.response_url,
   POSITION('email=' IN sr.response_url) + 6, -- Encontra o início do e-mail
    CASE
        WHEN POSITION('&' IN SUBSTRING(sr.response_url, POSITION('email=' IN sr.response_url) + 6)) > 0
        THEN POSITION('&' IN SUBSTRING(sr.response_url, POSITION('email=' IN sr.response_url) + 6)) - 1
        ELSE LENGTH(sr.response_url) - POSITION('email=' IN sr.response_url) - 5
    END) AS email_agent,
    case
      when regexp_extract(sr.response_url, '[?&]ticket_id=([^&]+)', 1) is null then regexp_extract(sr.response_url, '[?&]t_id=([^&]+)', 1)
      else regexp_extract(sr.response_url, '[?&]ticket_id=([^&]+)', 1)
    end as ticket_id,
    regexp_extract(sr.response_url, '[?&]contractid=([^&]+)', 1)  AS contractid,
    CASE
      WHEN ARRAY_AGG(CASE WHEN rc.answer_content IS NOT NULL THEN rc.answer_content END) FILTER(
        WHERE
          (rc.id_question = '2864547' AND sq.id_survey = 'f28163ea321f7cab')
       OR (rc.id_question = '2339118' AND sq.id_survey = 'f57ee5802b058791')
       OR (rc.id_question = '2338916' AND sq.id_survey = 'e8f1a7a60f12ba1b')
       OR (rc.id_question = '2396031' AND sq.id_survey = 'd52aad2976aab0d4')
       OR (rc.id_question = '2271243' AND sq.id_survey = 'ccecd6dbe925b337')
       OR (rc.id_question = '1926509' AND sq.id_survey = '9d64bf0e2f6faa48')
       OR (rc.id_question = '2939821' AND sq.id_survey = '84b8d08f88b16765')
       OR (rc.id_question = '2461801' AND sq.id_survey = '7c875afca4130e7a')
       OR (rc.id_question = '2933471' AND sq.id_survey = '7299d5b4e48d041a')
       OR (rc.id_question = '2339142' AND sq.id_survey = '6ef779f88ac6e1d9')
       OR (rc.id_question = '2760606' AND sq.id_survey = '4a2c89e54ea6c688') 
       OR (rc.id_question = '2339102' AND sq.id_survey = '34475b9efa7501d9') 
       OR (rc.id_question = '2271843' AND sq.id_survey = '29d847ff4d17cc18') 
       OR (rc.id_question = '2339133' AND sq.id_survey = '26a5ad040f5a9209') 
       OR (rc.id_question = '2768472' AND sq.id_survey = '20d6adebf70801b8') 
       OR (rc.id_question = '2513326' AND sq.id_survey = '12de0eedb5d98a27') 
       OR (rc.id_question = '2396109' AND sq.id_survey = '076f28a3e36bdb87') 
       OR (rc.id_question = '1835806' AND sq.id_survey = '00f46ff66c2ff389') 
      ) [1] in ('Extremely happy', '5', 'Muito satisfeito') then 5
      WHEN ARRAY_AGG(CASE WHEN rc.answer_content IS NOT NULL THEN rc.answer_content END) FILTER(
        WHERE 
          (rc.id_question = '2864547' AND sq.id_survey = 'f28163ea321f7cab')
       OR (rc.id_question = '2339118' AND sq.id_survey = 'f57ee5802b058791')
       OR (rc.id_question = '2338916' AND sq.id_survey = 'e8f1a7a60f12ba1b')
       OR (rc.id_question = '2396031' AND sq.id_survey = 'd52aad2976aab0d4')
       OR (rc.id_question = '2271243' AND sq.id_survey = 'ccecd6dbe925b337')
       OR (rc.id_question = '1926509' AND sq.id_survey = '9d64bf0e2f6faa48')
       OR (rc.id_question = '2939821' AND sq.id_survey = '84b8d08f88b16765')
       OR (rc.id_question = '2461801' AND sq.id_survey = '7c875afca4130e7a')
       OR (rc.id_question = '2933471' AND sq.id_survey = '7299d5b4e48d041a')
       OR (rc.id_question = '2339142' AND sq.id_survey = '6ef779f88ac6e1d9')
       OR (rc.id_question = '2760606' AND sq.id_survey = '4a2c89e54ea6c688') 
       OR (rc.id_question = '2339102' AND sq.id_survey = '34475b9efa7501d9') 
       OR (rc.id_question = '2271843' AND sq.id_survey = '29d847ff4d17cc18') 
       OR (rc.id_question = '2339133' AND sq.id_survey = '26a5ad040f5a9209') 
       OR (rc.id_question = '2768472' AND sq.id_survey = '20d6adebf70801b8') 
       OR (rc.id_question = '2513326' AND sq.id_survey = '12de0eedb5d98a27') 
       OR (rc.id_question = '2396109' AND sq.id_survey = '076f28a3e36bdb87') 
       OR (rc.id_question = '1835806' AND sq.id_survey = '00f46ff66c2ff389') 
      ) [1] in ('Happy', '4', 'Satisfeito') then 4
      WHEN ARRAY_AGG(CASE WHEN rc.answer_content IS NOT NULL THEN rc.answer_content END) FILTER(
        WHERE
          (rc.id_question = '2864547' AND sq.id_survey = 'f28163ea321f7cab')
       OR (rc.id_question = '2339118' AND sq.id_survey = 'f57ee5802b058791')
       OR (rc.id_question = '2338916' AND sq.id_survey = 'e8f1a7a60f12ba1b')
       OR (rc.id_question = '2396031' AND sq.id_survey = 'd52aad2976aab0d4')
       OR (rc.id_question = '2271243' AND sq.id_survey = 'ccecd6dbe925b337')
       OR (rc.id_question = '1926509' AND sq.id_survey = '9d64bf0e2f6faa48')
       OR (rc.id_question = '2939821' AND sq.id_survey = '84b8d08f88b16765')
       OR (rc.id_question = '2461801' AND sq.id_survey = '7c875afca4130e7a')
       OR (rc.id_question = '2933471' AND sq.id_survey = '7299d5b4e48d041a')
       OR (rc.id_question = '2339142' AND sq.id_survey = '6ef779f88ac6e1d9')
       OR (rc.id_question = '2760606' AND sq.id_survey = '4a2c89e54ea6c688') 
       OR (rc.id_question = '2339102' AND sq.id_survey = '34475b9efa7501d9') 
       OR (rc.id_question = '2271843' AND sq.id_survey = '29d847ff4d17cc18') 
       OR (rc.id_question = '2339133' AND sq.id_survey = '26a5ad040f5a9209') 
       OR (rc.id_question = '2768472' AND sq.id_survey = '20d6adebf70801b8') 
       OR (rc.id_question = '2513326' AND sq.id_survey = '12de0eedb5d98a27') 
       OR (rc.id_question = '2396109' AND sq.id_survey = '076f28a3e36bdb87') 
       OR (rc.id_question = '1835806' AND sq.id_survey = '00f46ff66c2ff389') 
      ) [1] in ('Neutro', '3', 'Neutral') then 3
      WHEN ARRAY_AGG(CASE WHEN rc.answer_content IS NOT NULL THEN rc.answer_content END) FILTER(
        WHERE
          (rc.id_question = '2864547' AND sq.id_survey = 'f28163ea321f7cab')
       OR (rc.id_question = '2339118' AND sq.id_survey = 'f57ee5802b058791')
       OR (rc.id_question = '2338916' AND sq.id_survey = 'e8f1a7a60f12ba1b')
       OR (rc.id_question = '2396031' AND sq.id_survey = 'd52aad2976aab0d4')
       OR (rc.id_question = '2271243' AND sq.id_survey = 'ccecd6dbe925b337')
       OR (rc.id_question = '1926509' AND sq.id_survey = '9d64bf0e2f6faa48')
       OR (rc.id_question = '2939821' AND sq.id_survey = '84b8d08f88b16765')
       OR (rc.id_question = '2461801' AND sq.id_survey = '7c875afca4130e7a')
       OR (rc.id_question = '2933471' AND sq.id_survey = '7299d5b4e48d041a')
       OR (rc.id_question = '2339142' AND sq.id_survey = '6ef779f88ac6e1d9')
       OR (rc.id_question = '2760606' AND sq.id_survey = '4a2c89e54ea6c688') 
       OR (rc.id_question = '2339102' AND sq.id_survey = '34475b9efa7501d9') 
       OR (rc.id_question = '2271843' AND sq.id_survey = '29d847ff4d17cc18') 
       OR (rc.id_question = '2339133' AND sq.id_survey = '26a5ad040f5a9209') 
       OR (rc.id_question = '2768472' AND sq.id_survey = '20d6adebf70801b8') 
       OR (rc.id_question = '2513326' AND sq.id_survey = '12de0eedb5d98a27') 
       OR (rc.id_question = '2396109' AND sq.id_survey = '076f28a3e36bdb87') 
       OR (rc.id_question = '1835806' AND sq.id_survey = '00f46ff66c2ff389') 
      )[1] in ('Unsatisfied', '2', 'Insatisfeito') then 2
      WHEN ARRAY_AGG(CASE WHEN rc.answer_content IS NOT NULL THEN rc.answer_content END) FILTER(
        WHERE
          (rc.id_question = '2864547' AND sq.id_survey = 'f28163ea321f7cab')
       OR (rc.id_question = '2339118' AND sq.id_survey = 'f57ee5802b058791')
       OR (rc.id_question = '2338916' AND sq.id_survey = 'e8f1a7a60f12ba1b')
       OR (rc.id_question = '2396031' AND sq.id_survey = 'd52aad2976aab0d4')
       OR (rc.id_question = '2271243' AND sq.id_survey = 'ccecd6dbe925b337')
       OR (rc.id_question = '1926509' AND sq.id_survey = '9d64bf0e2f6faa48')
       OR (rc.id_question = '2939821' AND sq.id_survey = '84b8d08f88b16765')
       OR (rc.id_question = '2461801' AND sq.id_survey = '7c875afca4130e7a')
       OR (rc.id_question = '2933471' AND sq.id_survey = '7299d5b4e48d041a')
       OR (rc.id_question = '2339142' AND sq.id_survey = '6ef779f88ac6e1d9')
       OR (rc.id_question = '2760606' AND sq.id_survey = '4a2c89e54ea6c688') 
       OR (rc.id_question = '2339102' AND sq.id_survey = '34475b9efa7501d9') 
       OR (rc.id_question = '2271843' AND sq.id_survey = '29d847ff4d17cc18') 
       OR (rc.id_question = '2339133' AND sq.id_survey = '26a5ad040f5a9209') 
       OR (rc.id_question = '2768472' AND sq.id_survey = '20d6adebf70801b8') 
       OR (rc.id_question = '2513326' AND sq.id_survey = '12de0eedb5d98a27') 
       OR (rc.id_question = '2396109' AND sq.id_survey = '076f28a3e36bdb87') 
       OR (rc.id_question = '1835806' AND sq.id_survey = '00f46ff66c2ff389') 
       )[1] in ('Muito insatisfeito', '1', 'Extremely unsatisfied') then 1
      ELSE NULL
    END AS rating,
        ARRAY_JOIN(
      ARRAY_AGG(distinct rc.answer_content) FILTER(
        WHERE(rc.id_question = '2864550' AND sq.id_survey = 'f28163ea321f7cab')
          OR (rc.id_question = '2339116' AND sq.id_survey = 'f57ee5802b058791')
          OR (rc.id_question = '2338914' AND sq.id_survey = 'e8f1a7a60f12ba1b')
          OR (rc.id_question = '2396044' AND sq.id_survey = 'd52aad2976aab0d4')
          OR (rc.id_question = '2271246' AND sq.id_survey = 'ccecd6dbe925b337')
          OR (rc.id_question = '1926532' AND sq.id_survey = '9d64bf0e2f6faa48')
          OR (rc.id_question = '2939824' AND sq.id_survey = '84b8d08f88b16765')
          OR (rc.id_question = '2461802' AND sq.id_survey = '7c875afca4130e7a')
          OR (rc.id_question = '2933474' AND sq.id_survey = '7299d5b4e48d041a')
          OR (rc.id_question = '2339141' AND sq.id_survey = '6ef779f88ac6e1d9')
          OR (rc.id_question = '2760607' AND sq.id_survey = '4a2c89e54ea6c688')
          OR (rc.id_question = '2339101' AND sq.id_survey = '34475b9efa7501d9')
          OR (rc.id_question = '2251570' AND sq.id_survey = '29d847ff4d17cc18')
          OR (rc.id_question = '2339132' AND sq.id_survey = '26a5ad040f5a9209')
          OR (rc.id_question = '2768475' AND sq.id_survey = '20d6adebf70801b8')
          OR (rc.id_question = '2513327' AND sq.id_survey = '12de0eedb5d98a27')
          OR (rc.id_question = '2396111' AND sq.id_survey = '076f28a3e36bdb87')
          OR (rc.id_question = '1869884' AND sq.id_survey = '00f46ff66c2ff389')
          ), ' | '
    ) as
    comment,
        ARRAY_JOIN(
      ARRAY_AGG(distinct rc.answer_content) FILTER(
        WHERE(
            rc.id_question in ('2864548', '2864549') AND sq.id_survey = 'f28163ea321f7cab')
        OR (rc.id_question = '2339115' AND sq.id_survey = 'f57ee5802b058791')
        OR (rc.id_question = '2396042' AND sq.id_survey = 'd52aad2976aab0d4')
        OR (rc.id_question = '2271245' AND sq.id_survey = 'ccecd6dbe925b337')
        OR (rc.id_question = '1926516' AND sq.id_survey = '9d64bf0e2f6faa48')
        OR (rc.id_question in ('2939823', '2939822') AND sq.id_survey = '84b8d08f88b16765')
        OR (rc.id_question in ('2933472','2933473') AND sq.id_survey = '7299d5b4e48d041a')
        OR (rc.id_question = '2339140' AND sq.id_survey = '6ef779f88ac6e1d9')
        OR (rc.id_question in ('2761473', '2761474') AND sq.id_survey = '4a2c89e54ea6c688')
        OR (rc.id_question = '2339100' AND sq.id_survey = '34475b9efa7501d9')
        OR (rc.id_question = '2251569' AND sq.id_survey = '29d847ff4d17cc18')
        OR (rc.id_question = '2339131' AND sq.id_survey = '26a5ad040f5a9209')
        OR (rc.id_question in ('2768473','2768474' ) AND sq.id_survey = '20d6adebf70801b8')
        OR (rc.id_question in ('2732165','2718002') AND sq.id_survey = '2087f705947a41b7')
        OR (rc.id_question = '2396110' AND sq.id_survey = '076f28a3e36bdb87')
        OR (rc.id_question = '1869883' AND sq.id_survey = '00f46ff66c2ff389')
        OR (rc.id_question in ('2732164','2718008') AND sq.id_survey = '006af3a7ab9cdd3b')
        ),' | '
    ) as justifications ,
    ARRAY_JOIN(ARRAY_AGG(distinct rc.answer_content) FILTER(
      WHERE 
          (rc.id_question = '2338912' AND sq.id_survey = 'e8f1a7a60f12ba1b')
       OR (rc.id_question = '2939820' AND sq.id_survey = '84b8d08f88b16765')
       OR (rc.id_question = '2461800' AND sq.id_survey = '7c875afca4130e7a')
       OR (rc.id_question = '2933470' AND sq.id_survey = '7299d5b4e48d041a')
       OR (rc.id_question = '2339138' AND sq.id_survey = '6ef779f88ac6e1d9')
       OR (rc.id_question = '2339129' AND sq.id_survey = '26a5ad040f5a9209') 
       OR (rc.id_question = '2768471' AND sq.id_survey = '20d6adebf70801b8') 
       OR (rc.id_question = '2513325' AND sq.id_survey = '12de0eedb5d98a27') 
       ),' | ') as resolution_rate
,
    ARRAY_AGG(CASE WHEN rc.answer_content IS NOT NULL THEN rc.answer_content END) FILTER(
      WHERE 
        (rc.id_question = '2864547' AND sq.id_survey = 'f28163ea321f7cab')
       OR (rc.id_question = '2339118' AND sq.id_survey = 'f57ee5802b058791')
       OR (rc.id_question = '2338916' AND sq.id_survey = 'e8f1a7a60f12ba1b')
       OR (rc.id_question = '2396031' AND sq.id_survey = 'd52aad2976aab0d4')
       OR (rc.id_question = '2271243' AND sq.id_survey = 'ccecd6dbe925b337')
       OR (rc.id_question = '1926509' AND sq.id_survey = '9d64bf0e2f6faa48')
       OR (rc.id_question = '2939821' AND sq.id_survey = '84b8d08f88b16765')
       OR (rc.id_question = '2461801' AND sq.id_survey = '7c875afca4130e7a')
       OR (rc.id_question = '2933471' AND sq.id_survey = '7299d5b4e48d041a')
       OR (rc.id_question = '2339142' AND sq.id_survey = '6ef779f88ac6e1d9')
       OR (rc.id_question = '2760606' AND sq.id_survey = '4a2c89e54ea6c688') 
       OR (rc.id_question = '2339102' AND sq.id_survey = '34475b9efa7501d9') 
       OR (rc.id_question = '2271843' AND sq.id_survey = '29d847ff4d17cc18') 
       OR (rc.id_question = '2339133' AND sq.id_survey = '26a5ad040f5a9209') 
       OR (rc.id_question = '2768472' AND sq.id_survey = '20d6adebf70801b8') 
       OR (rc.id_question = '2513326' AND sq.id_survey = '12de0eedb5d98a27') 
       OR (rc.id_question = '2396109' AND sq.id_survey = '076f28a3e36bdb87') 
       OR (rc.id_question = '1835806' AND sq.id_survey = '00f46ff66c2ff389') 
       ) [1] AS csat_score_category,
    ROW_NUMBER() OVER(
      PARTITION BY COALESCE(regexp_extract(sr.response_url, '[?&]ticket_id=([^&]+)', 1),
      regexp_extract(sr.response_url, '[?&]t_id=([^&]+)', 1),
      regexp_extract(sr.response_url, '[?&]contractid=([^&]+)', 1),
      regexp_extract(sr.response_url, '[?&]email=([^&]+)', 1))
      ORDER BY
        DATE(rc.ts_collected) ASC
    ) as answer_order
  FROM
    datalake_survicate.response_content AS rc
    LEFT JOIN datalake_survicate.survey_questions AS sq 
        ON sq.id_question = rc.id_question
    LEFT JOIN datalake_survicate.survey_responses AS sr 
        ON sr.id_response = rc.id_response
  WHERE
    sq.id_survey in (
      'f28163ea321f7cab',
      'f57ee5802b058791',
      'e8f1a7a60f12ba1b',
      'd52aad2976aab0d4',
      'ccecd6dbe925b337',
      '9d64bf0e2f6faa48',
      '84b8d08f88b16765',
      '7c875afca4130e7a',
      '7299d5b4e48d041a',
      '6ef779f88ac6e1d9',
      '4a2c89e54ea6c688',
      '34475b9efa7501d9',
      '29d847ff4d17cc18',
      '26a5ad040f5a9209',
      '20d6adebf70801b8',
      '12de0eedb5d98a27',
      '076f28a3e36bdb87',
      '00f46ff66c2ff389'
    )
    AND rc.ts_collected >= DATE('{load_start_date}')
  GROUP BY sq.id_survey,
    DATE(rc.ts_collected),
    CASE WHEN sq.id_survey = 'e8f1a7a60f12ba1b' THEN 'CX Padrão' --OK
         WHEN sq.id_survey = '26a5ad040f5a9209' THEN 'Serfin' --OK
         WHEN sq.id_survey = '6ef779f88ac6e1d9' THEN 'Serfin_gatilho' --OK
         WHEN sq.id_survey = '7c875afca4130e7a' THEN 'Quintocred atendimento' --OK
         WHEN sq.id_survey = '12de0eedb5d98a27' THEN 'Collection' --OK
         WHEN sq.id_survey = 'f57ee5802b058791' THEN 'Chaves Offb' --OK
         WHEN sq.id_survey = '34475b9efa7501d9' THEN 'Chaves Onb' --OK
         WHEN sq.id_survey = '29d847ff4d17cc18' THEN 'Vistoria entrada' --OK
         WHEN sq.id_survey = 'f28163ea321f7cab' THEN 'Reparos Ong' --OK
         WHEN sq.id_survey = 'd52aad2976aab0d4' THEN 'Budget Approval' --OK
         WHEN sq.id_survey = 'ccecd6dbe925b337' THEN 'Vistoria entrada' --OK
         WHEN sq.id_survey = '9d64bf0e2f6faa48' THEN 'Vistoria saída' -- OK
         WHEN sq.id_survey = '84b8d08f88b16765' THEN 'Mediação'-- OK
         WHEN sq.id_survey = '7299d5b4e48d041a' THEN 'PP Multi'--OK
         WHEN sq.id_survey = '4a2c89e54ea6c688' THEN 'QuintoCred [inadimplencia/acionamento]' -- OK
         WHEN sq.id_survey = '20d6adebf70801b8' THEN 'Pagamentos' -- OK
         WHEN sq.id_survey = '076f28a3e36bdb87' THEN 'Budget Approval' -- OK
         WHEN sq.id_survey = '00f46ff66c2ff389' THEN 'Vistoria saída' -- OK
    ELSE sq.survey_name END,
    sr.id_response,
    sr.response_url
), quinto_cred AS (
select
  h.sk_ticket,
  h.sk_requester,
  group_name,
  CASE WHEN t.role = 'end-user' THEN 'tenant'
      WHEN t.role IS NULL THEN ''
    ELSE 'imobiliária parceira' END AS role
  from dw_velo.fact_velo_ticket_history h
  left join dw_velo.dim_velo_ticket_users t
    on h.sk_requester = t.sk_ticket_user
  where ticket_order = 1
), fact_contract_people2 AS (
    SELECT 
      sk_user,
      sk_contract,
      contract_role
    FROM
      dw_rent.fact_contract_people
    WHERE is_contract_user 
    AND contract_role IN ('tenant', 'landlord')
), final AS (
    select
    csat.id_survey,
    csat.survey_name,
    message_id,
    posted_at,
    rating,
    COALESCE(resolution_rate, '') AS resolution_rate,
    COALESCE(csat_score_category, '') AS csat_score_category,
    CASE 
    WHEN NULLIF(comment, '') IS NULL 
        AND NULLIF(justifications, '') IS NULL 
        THEN NULL
    WHEN NULLIF(comment, '') IS NOT NULL 
        AND NULLIF(justifications, '') IS NULL 
        AND (csat_score_category = '2' OR csat_score_category = '1' OR csat_score_category = 'Muito insatisfeito' OR csat_score_category = 'Insatisfeito'
                            OR csat_score_category = 'Extremely unsatisfied' OR csat_score_category = 'Unsatisfied')
        THEN 'Motivo da minha insatisfação: ' || comment 
    WHEN NULLIF(comment, '') IS NOT NULL 
        AND NULLIF(justifications, '') IS NULL 
        AND (csat_score_category = '3' OR csat_score_category = 'Neutral' OR csat_score_category = 'Neutro')
        THEN 'Motivo da minha nota: ' || comment
    WHEN NULLIF(comment, '') IS NOT NULL 
        AND NULLIF(justifications, '') IS NULL 
        AND (csat_score_category = '5' OR csat_score_category = '4' OR csat_score_category = 'Happy' OR csat_score_category = 'Muito satisfeito'
                            OR csat_score_category = 'Extremely happy' OR csat_score_category = 'Satisfeito')
        THEN 'Motivo da minha satisfação: ' || comment 
    WHEN NULLIF(comment, '') IS NULL 
        AND NULLIF(justifications, '') IS NOT NULL 
        AND (csat_score_category = '2' OR csat_score_category = '1' OR csat_score_category = 'Muito insatisfeito' OR csat_score_category = 'Insatisfeito'
                            OR csat_score_category = 'Extremely unsatisfied' OR csat_score_category = 'Unsatisfied')
        THEN 'Justificativa: ' || justifications 
    WHEN NULLIF(comment, '') IS NULL 
        AND NULLIF(justifications, '') IS NOT NULL 
        AND (csat_score_category = '3' OR csat_score_category = 'Neutral' OR csat_score_category = 'Neutro')
        THEN 'Justificativa: ' || justifications 
    WHEN NULLIF(comment, '') IS NULL 
        AND NULLIF(justifications, '') IS NOT NULL 
        AND (csat_score_category = '5' OR csat_score_category = '4' OR csat_score_category = 'Happy' OR csat_score_category = 'Muito satisfeito'
                            OR csat_score_category = 'Extremely happy' OR csat_score_category = 'Satisfeito')
        THEN 'Justificativa: ' || justifications
    WHEN NULLIF(comment, '') IS NOT NULL 
        AND NULLIF(justifications, '') IS NOT NULL 
        AND (csat_score_category = '2' OR csat_score_category = '1' OR csat_score_category = 'Muito insatisfeito' OR csat_score_category = 'Insatisfeito'
                            OR csat_score_category = 'Extremely unsatisfied' OR csat_score_category = 'Unsatisfied')
        THEN 'Motivo da minha insatisfação: ' || comment || ' Justificativa: ' || justifications
    WHEN NULLIF(comment, '') IS NOT NULL 
        AND NULLIF(justifications, '') IS NOT NULL 
        AND (csat_score_category = '3' OR csat_score_category = 'Neutral' OR csat_score_category = 'Neutro')
        THEN 'Motivo da minha nota: ' || comment || ' Justificativa: ' || justifications
    WHEN NULLIF(comment, '') IS NOT NULL 
        AND NULLIF(justifications, '') IS NOT NULL 
        AND (csat_score_category = '5' OR csat_score_category = '4' OR csat_score_category = 'Happy' OR csat_score_category = 'Muito satisfeito'
                            OR csat_score_category = 'Extremely happy' OR csat_score_category = 'Satisfeito')
        THEN 'Motivo da minha satisfação: ' || comment || ' Justificativa: ' || justifications
    ELSE NULL
    END AS text,
    COALESCE(ticket_id, '') AS ticket_id,
    CASE 
        WHEN REGEXP_LIKE(COALESCE(tkt.agent_email, csat.email_agent), '^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{{2,}}$') 
        THEN COALESCE(tkt.agent_email, csat.email_agent) 
        ELSE '' 
    END AS agent_email,
    COALESCE(agent_company, '') AS agent_company,
    COALESCE(department, quinto_cred.group_name, 
    '') AS department,
    CASE WHEN csat.id_survey in ('29d847ff4d17cc18', '00f46ff66c2ff389', '076f28a3e36bdb87', '7299d5b4e48d041a') THEN 'landlord'
        WHEN csat.id_survey in ('ccecd6dbe925b337', '9d64bf0e2f6faa48', 'd52aad2976aab0d4') THEN 'tenant'
        ELSE COALESCE(tkt.customer_type, c.contract_role, c1.contract_role, quinto_cred.role) END AS customer_type,
    COALESCE(CAST(tkt.id_user AS STRING), CAST(c.sk_user AS STRING)
    ,CAST(quinto_cred.sk_requester AS STRING), CAST(c1.sk_user AS STRING), CAST(c2.sk_user AS STRING), CAST(c3.sk_user AS STRING)
    , CAST(s.id_respondent AS STRING), '') AS sk_user,
    offer_id, 
    tkt.id_ticket, 
    COALESCE(CAST(c.sk_contract AS STRING), csat.contractid, CAST(tkt.sk_contract AS STRING)) AS sk_contract
    from
    base_respostas AS csat
    left join dados_tickets as tkt 
        on csat.ticket_id = tkt.id_ticket
    left join fact_contract_people c 
        ON csat.contractid = CAST(c.sk_contract AS STRING)
    left join fact_contract_people c1 
        ON tkt.sk_contract = CAST(c1.sk_contract AS STRING) -- PRECISA DISSO?
    left join fact_contract_people2 c2 
        ON tkt.sk_contract = CAST(c2.sk_contract AS STRING) 
        and c2.contract_role = 'landlord'
        and csat.id_survey in ('29d847ff4d17cc18', '00f46ff66c2ff389', '076f28a3e36bdb87', '7299d5b4e48d041a')
    left join fact_contract_people2 c3 
        ON tkt.sk_contract = c3.sk_contract 
        and c3.contract_role = 'tenant'
        and csat.id_survey in ('ccecd6dbe925b337', '9d64bf0e2f6faa48', 'd52aad2976aab0d4')
    LEFT JOIN quinto_cred 
        ON CAST(quinto_cred.sk_ticket AS STRING) = csat.ticket_id
        and (csat.survey_name LIKE '%QuintoCred%')
    LEFT JOIN datalake_survicate.inspections_surveys s 
        ON csat.contractid = s.id_contract 
    where
    answer_order = 1 
  ), final_2 AS (
    select
  --id_survey,
    survey_name AS csat_campanha,
    message_id,
    DATE(posted_at) posted_at,
    rating,
    CASE WHEN resolution_rate = 'Não' THEN 'FALSE' WHEN resolution_rate = 'Sim' THEN 'TRUE' ELSE '' END AS resolution,
    CASE WHEN csat_score_category = '5' OR csat_score_category = '4' or csat_score_category = 'Happy' or csat_score_category = 'Muito satisfeito'
    or csat_score_category = 'Extremely happy'  or csat_score_category = 'Satisfeito' THEN 'promoter'
        WHEN csat_score_category = '3'  OR csat_score_category = 'Neutral'  OR csat_score_category = 'Neutro' THEN 'passive'
        WHEN csat_score_category = '2' OR csat_score_category = '1' OR csat_score_category = 'Muito insatisfeito' OR csat_score_category = 'Insatisfeito'
        OR csat_score_category = 'Extremely unsatisfied'OR csat_score_category = 'Unsatisfied' THEN 'detractor' ELSE '' END AS csat_score_category,
    text,
    ticket_id,
    agent_email,
    agent_company,
    department,
    CASE WHEN customer_type IS NULL THEN '' 
        WHEN customer_type like '%inquilino%' OR customer_type like '%buyer%' THEN 'tenant' 
        WHEN customer_type like '%proprietário%' OR customer_type like '%seller%' THEN 'landlord' 
        ELSE customer_type END AS customer_type,
    MIN(CASE WHEN sk_user = '-1' THEN '' ELSE sk_user END) AS author_id,
    MIN(CASE WHEN sk_user IS NOT NULL AND sk_user <> '-1' AND sk_user <> '' THEN CONCAT(message_id, '_', sk_user)
            WHEN ticket_id IS NOT NULL AND ticket_id <> '' THEN CONCAT(message_id, '_', ticket_id)
            ELSE message_id
    END) AS account_id,--TRAZER TICKET IS SE SK_USER NULO
    CASE WHEN sk_contract = '0' THEN '' ELSE sk_contract END AS sk_contract
    from final 
    GROUP BY 1,2,3,4,5,6,7,8,9,10,11,12,15
)
SELECT 
    csat_campanha,
    message_id,
    date_format(posted_at, 'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'') AS posted_at,
    rating,
    resolution,
    csat_score_category,
    text,
    ticket_id,
    agent_email,
    agent_company,
    department,
    customer_type,
    author_id,
    CASE 
            WHEN customer_type <> '' THEN CONCAT(account_id, '_', customer_type)
            ELSE account_id
        END AS account_id,
    sk_contract,
    year(posted_at) AS year,
    month(posted_at) AS month,
    day(posted_at) AS day,
    NOW() AS ts_load
FROM 
  final_2
WHERE 
    rating is not null