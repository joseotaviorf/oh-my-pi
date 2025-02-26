WITH b2b_listings AS (--all b2b listings with contracts signed
  SELECT DISTINCT
    rf.sk_contract,
    hl.is_b2b
  FROM
    dw_rent.fact_listing_rent_flows AS rf
  INNER JOIN
    dw_rent.dim_house_listing AS hl
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
    CURRENT_DATE() - INTERVAL '15' day AS dt_recap,
    INT(MONTHS_BETWEEN(CURRENT_DATE(), dc.dt_start)) AS age,
    INT(MONTHS_BETWEEN(CURRENT_DATE() - INTERVAL '15' day, dc.dt_start)) AS age_recap,
    CASE
      WHEN DAY(dt_start) = DAY(CURRENT_DATE())
        AND INT(MONTHS_BETWEEN(CURRENT_DATE(), dc.dt_start)) % 6 = 0 THEN 'birthday'
      WHEN DAY(dt_start) = DAY(CURRENT_DATE() - INTERVAL '15' day)
        AND INT(MONTHS_BETWEEN(CURRENT_DATE() - INTERVAL '15' day, dc.dt_start)) % 6 = 0 THEN 'recap_birthday'
      ELSE null
    END AS birth_type
  FROM
    dw_rent.dim_contract AS dc
  LEFT JOIN
    b2b_listings AS bl
      ON dc.sk_contract = bl.sk_contract
  LEFT JOIN
    datalake_offboarding.contract_termination AS ct
      ON dc.sk_contract = ct.id_contract
      AND ct.status != 'CANCELED'
  WHERE
    dc.country_code = 'BR'
    AND dc.status = 'Ativo'
    AND ct.id_contract IS NULL
    AND bl.sk_contract IS NULL
    AND dc.rental_administrator = 'QUINTOANDAR'
    AND INT(MONTHS_BETWEEN(CURRENT_DATE(), dc.dt_start)) > 5
),
status_send AS (--Evaluat every ticket related to an birthday contract or contract in recap
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
        AND (ft.front_or_back = 'back' or dp.team IS NOT NULL) THEN 1
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
      ON ft.sk_ticket = ft.sk_ticket
  LEFT JOIN
    dw_customer_support.dim_department AS dp
      ON ft.sk_main_department = dp.sk_department
      AND (dp.department IN ('Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions'))
  WHERE
    c.birth_type IS NOT NULL
),
contracts_to_send AS (--Select all contracts that can receive the nps survey
  SELECT
    sk_contract,
    age,
    age_recap,
    MAX(birth_type) AS birth_type,
    MAX(flg_not_send) AS flg_not_send,
    MAX(flg_recap_send) AS flg_recap_send
  FROM
    status_send
  GROUP BY
    1, 2, 3
  HAVING
    (MAX(birth_type) = 'birthday' AND MAX(flg_not_send) = 0)
    OR (MAX(birth_type) = 'recap_birthday' AND MAX(flg_recap_send) = 1)
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
    'Proprietário' AS customer_type,
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
  LEFT JOIN
    datalake_ebdb_clean.user AS u
      ON (cp.email = u.email
        OR cp.email = u.alternative_email)
  LEFT JOIN
    datalake_ebdb_customer_contact_identification.customer_contact_identification AS cci
      ON cp.email = cci.customer_contact
  LEFT JOIN
    datalake_ebdb_clean.user_pro_owner AS po
      ON (cp.id_user = po.id_user
        OR u.id = po.id_user
        OR cci.id_user = po.id_user)
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
  '12 meses' AS campaign_step,
  'Proprietário' AS customer_type,
  '1234' AS customer_cpf,
  '1234' AS id_user,
  'true' AS campaign_type,
  'id_contract' AS driver_type,
  '1234' AS id_driver
