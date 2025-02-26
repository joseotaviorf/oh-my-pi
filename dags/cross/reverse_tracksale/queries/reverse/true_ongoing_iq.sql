WITH contracts AS (--all considered contracts, but without birthday criteria applied
  SELECT
    dc.sk_contract,
    dc.dt_start,
    CURRENT_DATE() - INTERVAL '15' day AS dt_recap,
    INT(MONTHS_BETWEEN(CURRENT_DATE(), dc.dt_start)) AS age,
    INT(MONTHS_BETWEEN(CURRENT_DATE() - INTERVAL '15' day, dc.dt_start)) AS age_recap,
    CASE
      WHEN DAY(dt_start) = DAY(CURRENT_DATE())
        AND INT(MONTHS_BETWEEN(CURRENT_DATE(), dc.dt_start)) % 6 = 0 THEN 'birthday'
      WHEN DAY(dt_start) = DAY(CURRENT_DATE() - INTERVAL '15' day)
        AND INT(MONTHS_BETWEEN(CURRENT_DATE() - INTERVAL '15' day, dc.dt_start )) % 6 = 0 THEN 'recap_birthday'
      ELSE NULL
    END AS birth_type
  FROM
    dw_rent.dim_contract AS dc
  LEFT JOIN
    datalake_offboarding.contract_termination AS ct
      ON dc.sk_contract = ct.id_contract
      AND ct.status != 'CANCELED'
  WHERE
    dc.country_code = 'BR'
    AND dc.status = 'Ativo'
    AND ct.id_contract IS NULL
    AND dc.rental_administrator = 'QUINTOANDAR'
    AND INT(MONTHS_BETWEEN(CURRENT_DATE(), dc.dt_start)) > 5
),
stock_contracts AS (  -- Contracts that must be filtered out due to being stock type
  SELECT DISTINCT
    op.id_contract
  FROM
    datalake_invoice.overdue_portfolio_timeline AS op
  WHERE
    op.debtor_type = 'Stock'
    AND op.dt_reference BETWEEN (DATE(NOW()) - INTERVAL '180' DAY) AND DATE(NOW())
),
status_send AS (--Evaluat every ticket related to an birthday contract ORcontract in recap
  SELECT
    c.sk_contract,
    c.age,
    c.age_recap,
    c.birth_type,
    ft.front_or_back,
    dp.team,
    c.dt_start,
    c.dt_recap,
    ft.ts_created AS ts_started,
    ft.ts_solved,
    CASE
      WHEN c.birth_type = 'birthday'
        AND ft.sk_ticket IS NOT NULL
        AND ft.ts_solved IS NULL
        AND (ft.front_or_back = 'back' OR dp.team IS NOT NULL) THEN 1
      ELSE 0
    END AS flg_not_send,
    CASE
      WHEN c.birth_type = 'recap_birthday'
        AND ft.sk_ticket IS NOT NULL
        AND ft.ts_created < c.dt_recap
        AND (ft.ts_solved >= c.dt_recap OR ft.ts_solved IS NULL)
        AND (ft.front_or_back = 'back' OR dp.team IS NOT NULL) THEN 1
      ELSE 0
    END AS flg_recap_send
  FROM
    contracts AS c
  LEFT JOIN
    dw_customer_support.dim_ticket AS dt
      ON c.sk_contract = dt.sk_contract
      AND dt.sk_contract IS NOT NULL
  LEFT JOIN
    dw_customer_support.fact_tickets AS ft
      ON dt.sk_ticket = ft.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_department AS dp
      ON ft.sk_main_department = dp.sk_department
      AND (dp.department IN ('Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions'))
  WHERE
    c.birth_type IS NOT NULL
    AND c.sk_contract NOT IN (SELECT id_contract FROM stock_contracts)
),
contracts_to_send AS (--Select all contracts that can receive the nps survey
  SELECT
    ss.sk_contract,
    ss.age,
    ss.age_recap,
    MAX(ss.birth_type) AS birth_type,
    MAX(ss.flg_not_send) AS flg_not_send,
    MAX(ss.flg_recap_send) AS flg_recap_send
  FROM
    status_send AS ss
  GROUP BY
    1, 2, 3
  HAVING
    (MAX(ss.birth_type) = 'birthday' AND MAX(ss.flg_not_send) = 0)
    OR (MAX(ss.birth_type) = 'recap_birthday' AND MAX(ss.flg_recap_send) = 1)
),
people_to_send AS (--Selected all people than can receive the nps survey
  SELECT
    cp.name AS customer_name,
    cp.email AS customer_email,
    cp.phone_number AS customer_phone,
    CASE
      WHEN cs.birth_type = 'birthday' THEN STRING(cs.age) || ' meses'
      ELSE STRING(cs.age_recap) || ' meses'
    END AS campaign_step,
    'Inquilino' AS customer_type,
    cp.cpf AS customer_cpf,
    cp.id_user,
    'true' AS campaign_type,
    'id_contract' AS driver_type,
    cp.id_contract AS id_driver
  FROM
    datalake_ebdb_clean.contract_person AS cp
  INNER JOIN
    contracts_to_send AS cs
      ON cp.id_contract = cs.sk_contract
  WHERE
    cp.type IN ('Inquilino','Morador')
    AND cp.email IS NOT NULL
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
  '12 meses' AS campaign_step,
  'Inquilino' AS customer_type,
  '1234' AS customer_cpf,
  '1234' AS id_user,
  'true' AS campaign_type,
  'id_contract' AS driver_type,
  '1234' AS id_driver
