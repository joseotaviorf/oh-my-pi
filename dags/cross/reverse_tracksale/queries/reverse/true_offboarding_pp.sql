WITH b2b_listings AS (
  SELECT DISTINCT 
    rf.sk_contract,
    hl.is_b2b 
  FROM
    dw_public.fact_listing_rent_flows AS rf 
  INNER JOIN 
    dw_public.dim_house_listing hl 
      ON rf.sk_house_listing = hl.sk_house_listing
      AND hl.is_b2b = true
  WHERE 
    rf.sk_contract != -1
    AND rf.sk_contract_signed_date > 0
),
contracts AS (
  SELECT 
    dc.sk_contract,
    dc.dt_start,
    ct.ts_termination_finished,
    CURRENT_DATE() - INTERVAL '15' day AS dt_recap,
    DATEDIFF(DATE(ct.ts_termination_finished), CURRENT_DATE()) AS ndays_termination2today,
    CASE 
      WHEN DATEDIFF(CURRENT_DATE(), DATE(ct.ts_termination_finished)) = 2 THEN 'termination'
      WHEN DATEDIFF(CURRENT_DATE(), DATE(ct.ts_termination_finished)) = 15 THEN 'recap_termination'
      ELSE NULL 
    END AS termination_type
  FROM
    dw_public.dim_contract AS dc 
  INNER JOIN 
    datalake_offboarding.contract_termination AS ct 
      ON dc.sk_contract = ct.id_contract
  LEFT JOIN 
    b2b_listings AS bl 
      ON dc.sk_contract = bl.sk_contract
  WHERE
    dc.country_code = 'BR'
    AND ct.status = 'DONE'
    AND bl.sk_contract IS NULL	
    AND ct.dt_termination >= dc.dt_start
    AND dc.rental_administrator = 'QUINTOANDAR'
),
status_send AS (
  SELECT 
    c.sk_contract,
    ft.sk_ticket,
    c.ndays_termination2today,
    c.termination_type,
    dp.department,
    dp.team,
    c.dt_start,
    c.ts_termination_finished,
    c.dt_recap,
    ft.ts_started,
    ft.ts_solved,
    CASE 
      WHEN (dp.department IN ('Rescisão - Despejo [OFF][POS][BACK]','Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions'))
        OR (c.termination_type = 'termination' 
        AND ft.sk_ticket IS NOT NULL 
        AND ft.ts_solved IS NULL 
        AND dp.sk_department IS NOT NULL) THEN 1 
      ELSE 0 
    END AS flg_not_send,                                                     
    CASE 
      WHEN (dp.department IN ('Rescisão - Despejo [OFF][POS][BACK]','Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions')) THEN 0
      WHEN c.termination_type = 'recap_termination' 
        AND ft.sk_ticket IS NOT NULL 
        AND ft.ts_started < c.dt_recap + INTERVAL '2' day
        AND dp.department IN ('Offboarding [OFF] [POS] [BACK]', 'Atendimento Escalado [OFF] [POS] [BACK]', 'Proteção QuintoAndar [OFF] [POS] [BACK]')
        AND (ft.ts_solved >= c.dt_recap + INTERVAL '2' day OR ft.ts_solved IS NULL) THEN 1
      ELSE 0
    END AS flg_recap_send
  FROM 
    contracts AS c
  LEFT JOIN 
    dw_customer_support.fact_ticket AS ft 
      ON c.sk_contract = ft.sk_contract 
      AND ft.sk_contract IS NOT NULL
  LEFT JOIN
    dw_customer_support.dim_department AS dp 
      ON ft.sk_main_department = dp.sk_department 
      AND (dp.department IN ('Offboarding [OFF] [POS] [BACK]', 'Atendimento Escalado [OFF] [POS] [BACK]','Proteção QuintoAndar [OFF] [POS] [BACK]','Rescisão - Despejo [OFF][POS][BACK]','Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions'))
  WHERE
    c.termination_type IS NOT NULL  --('termination', 'recap_termination')
),
contracts_to_send AS (
  SELECT 
    sk_contract,
    ndays_termination2today,
    MAX(termination_type) AS termination_type,
    MAX(flg_not_send) AS flg_not_send,
    MAX(flg_recap_send) AS flg_recap_send
  FROM 
    status_send
  GROUP BY 
    1, 2
  HAVING 
    (MAX(termination_type) = 'termination' AND MAX(flg_not_send) = 0)
    OR (MAX(termination_type) = 'recap_termination' AND MAX(flg_recap_send) = 1)
),
people_to_send AS (
  SELECT 
    cp.name AS customer_name,
    cp.email AS customer_email,
    cp.phone_number AS customer_phone,
    'Rescisão' AS campaign_step,
    'Proprietário' AS customer_type,
    cp.cpf AS customer_cpf,
    cp.id_user,
    'true' AS campaign_type,
    'contract' AS driver_type,
    cp.id_contract AS id_driver
  FROM 
    datalake_ebdb_clean.contract_person AS cp 
  INNER JOIN 
    contracts_to_send AS cs 
      ON cp.id_contract = cs.sk_contract
  LEFT JOIN
    datalake_ebdb_clean.user AS u
      ON cp.email = u.email
  LEFT JOIN 
    datalake_ebdb_clean.user_pro_owner AS po 
      ON (cp.id_user = po.id_user
        OR u.id = po.id_user)
      AND po.is_active = true 
  WHERE 
    cp.type IN ('Proprietario')
    AND po.is_active IS NULL
)
SELECT
  customer_name,
  customer_email,
  customer_phone,
  campaign_step,
  customer_type,
  customer_cpf,
  id_user,
  campaign_type,
  driver_type,
  id_driver
FROM 
  people_to_send
UNION ALL
SELECT
  'Teste Disparo' AS customer_name,
  'testes.disparos.5a@gmail.com' AS customer_email,
  '+5511123456789' AS customer_phone,
  'Rescisão' AS campaign_step,
  'Proprietário' AS customer_type,
  '1234' AS customer_cpf,
  '1234' AS id_user,
  'true' AS campaign_type,
  'contract' AS driver_type,
  '1234' AS id_driver