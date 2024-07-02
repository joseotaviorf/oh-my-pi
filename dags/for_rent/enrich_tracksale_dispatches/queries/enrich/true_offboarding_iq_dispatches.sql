WITH b2b_listings AS (
  SELECT
    rf.sk_contract,
    b2b.is_b2b
  FROM 
    dw_rent.fact_listing_rent_flows AS rf
  JOIN 
    datalake_b2b.house_listing AS b2b
      ON rf.sk_house_listing = b2b.id_house_listing
      AND b2b.is_b2b
  WHERE
    rf.sk_contract != -1
    AND rf.sk_contract_signed_date > 0
),
contracts AS (
  SELECT
    c.id AS id_contract,
    c.dt_started,
    ct.ts_termination_finished,
    DATE_ADD(ad.date, 1) - INTERVAL '15' DAY AS dt_recap,
    DATEDIFF(DATE_ADD(ad.date, 1), DATE(ct.ts_termination_finished)) AS ndays_termination2today,
    CASE
      WHEN DATEDIFF(DATE_ADD(ad.date, 1), DATE(ct.ts_termination_finished)) = 2 THEN 'termination'
      WHEN DATEDIFF(DATE_ADD(ad.date, 1), DATE(ct.ts_termination_finished)) = 15 THEN 'recap_termination'
      ELSE NULL
    END AS termination_type
  FROM
    datalake_ebdb_contract.contract AS c
  JOIN
    datalake_quintoandar.aux_date AS ad
      ON ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  INNER JOIN
    datalake_offboarding.contract_termination AS ct
      ON c.id = ct.id_contract
  LEFT JOIN
    b2b_listings AS bl
      ON c.id = bl.sk_contract
  WHERE
    c.country_code = 'BR'
    AND ct.status = 'DONE'
    AND bl.sk_contract IS NULL
    AND ct.dt_termination >= c.dt_started
    AND c.rental_administrator = 'QUINTOANDAR'
),
stock_contracts AS (  -- Contracts that must be filtered out due to being stock type in the last 180 days
  SELECT DISTINCT
    op.id_contract
  FROM
    datalake_invoice.overdue_portfolio_timeline AS op
    -- We're not considering this table as a dependency for the DAG due to being a context that runs during by the day and is out of our SLA.
    -- So related to this data, we're only dealing here with D-2 results.
  JOIN
    datalake_quintoandar.aux_date AS ad
      ON ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  WHERE
    op.debtor_type = 'Stock'
    AND op.dt_reference BETWEEN DATE(DATE_ADD(ad.date, 1) - INTERVAL '180' DAY) AND DATE(DATE_ADD(ad.date, 1))
),
status_send AS (
  SELECT
    c.id_contract,
    ut.id_ticket,
    c.ndays_termination2today,
    c.termination_type,
    dp.department,
    dp.team,
    c.dt_started,
    c.ts_termination_finished,
    c.dt_recap,
    ut.ts_started,
    ut.ts_solved,
    CASE
      WHEN (dp.department IN ('Rescisão - Despejo [OFF][POS][BACK]', 'Rescisão por Inadimplência [OFF] [POS] [BACK]', 'Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions'))
        OR (c.termination_type = 'termination'
        AND ut.id_ticket IS NOT NULL
        AND ut.ts_solved IS NULL
        AND dp.sk_department IS NOT NULL) THEN 1
       ELSE 0
     END AS flg_not_send,
    CASE
      WHEN (dp.department IN ('Rescisão - Despejo [OFF][POS][BACK]', 'Rescisão por Inadimplência [OFF] [POS] [BACK]', 'Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions')) THEN 0
      WHEN c.termination_type = 'recap_termination'
        AND ut.id_ticket IS NOT NULL
        AND ut.ts_started < c.dt_recap  + INTERVAL '2' DAY
        AND dp.department IN ('Offboarding [OFF] [POS] [BACK]', 'Atendimento Escalado [OFF] [POS] [BACK]', 'Proteção QuintoAndar [OFF] [POS] [BACK]')
        AND (ut.ts_solved >= c.dt_recap + INTERVAL '2' DAY OR ut.ts_solved IS NULL) THEN 1
      ELSE 0
     END AS flg_recap_send
  FROM
    contracts AS c
  LEFT JOIN
    datalake_customer_support.unified_tickets AS ut
      ON c.id_contract = ut.id_contract
      AND ut.id_contract IS NOT NULL
  LEFT JOIN
    dw_customer_support.dim_department AS dp
      ON ut.id_main_department = dp.sk_department
      AND (dp.department IN ('Offboarding [OFF] [POS] [BACK]', 'Atendimento Escalado [OFF] [POS] [BACK]','Proteção QuintoAndar [OFF] [POS] [BACK]','Rescisão - Despejo [OFF][POS][BACK]', 'Rescisão por Inadimplência [OFF] [POS] [BACK]', 'Notificação Extrajudicial [CE] [POS] [BACK]','Dados Bancários [CE] [POS] [BACK]','CX ReclameAqui Adquiridas [CE] [POS] [BACK]')
        OR dp.team IN ('Casos Especiais','Ouvidoria','ReclameAqui','Evictions'))
  WHERE
    c.termination_type IS NOT NULL  --('termination', 'recap_termination')
    AND c.id_contract NOT IN (SELECT id_contract FROM stock_contracts)
),
contracts_to_send AS (
  SELECT
    id_contract,
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
)
SELECT
  cp.name AS customer_name,
  cp.email AS customer_email,
  cp.phone_number AS customer_phone,
  'Rescisão' AS campaign_step,
  'Inquilino' AS customer_type,
  cp.cpf AS customer_cpf,
  cp.id_user,
  'true' AS campaign_type,
  'contract' AS driver_type,
  cp.id_contract AS id_driver,
  YEAR(DATE_ADD(ad.date, 1)) AS year,
  MONTH(DATE_ADD(ad.date, 1)) AS month,
  DAY(DATE_ADD(ad.date, 1)) AS day
FROM
  datalake_ebdb_clean.contract_person AS cp
INNER JOIN
  contracts_to_send AS cs
    ON cp.id_contract = cs.id_contract
JOIN
  datalake_quintoandar.aux_date AS ad
    ON ad.date BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
LEFT JOIN
  datalake_ebdb_clean.user AS u
    ON cp.email = u.email
LEFT JOIN
  datalake_ebdb_clean.user_pro_owner AS po
    ON (cp.id_user = po.id_user
      OR u.id = po.id_user)
    AND po.is_active = TRUE
WHERE
  po.is_active IS NULL
  AND cp.type IN ('Inquilino','Morador')