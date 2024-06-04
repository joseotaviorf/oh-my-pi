WITH users AS (
  SELECT
    'user' AS source,
    sk_user,
    nome AS name,
    email,
    CAST(NULL AS STRING) AS sk_personal_document /* enabling an 'OR' join with unique matches */
  FROM dw_public.dim_user AS u
  GROUP BY
    1,
    2,
    3,
    4,
    5
), people AS (
  SELECT
    'cpf' AS source,
    CAST(NULL AS INT) AS sk_user,
    dc.full_name AS name,
    dc.email,
    fc.sk_personal_document
  FROM dw_rent.fact_contract_people AS fc
  LEFT JOIN dw_rent.dim_contract_person AS dc
    ON dc.sk_contract_person = fc.sk_contract_person
  WHERE
    sk_user = -1 AND (
      fc.is_valid_cpf = TRUE OR fc.is_valid_cnpj = TRUE
    )
  GROUP BY
    1,
    2,
    3,
    4,
    5
), customers AS (
  SELECT
    *
  FROM users
  UNION ALL
  SELECT
    *
  FROM people
), clean_contract_people AS (
  SELECT
    sk_personal_document,
    MAX(sk_contract_person) AS sk_max_contract_person
  FROM dw_rent.fact_contract_people
  WHERE
    (
      is_valid_cpf = TRUE OR is_valid_cnpj = TRUE
    ) AND is_last_contract = TRUE
  GROUP BY
    1
), clean_contract_users AS (
  SELECT
    sk_user,
    MAX(sk_contract_person) AS sk_max_contract_person
  FROM dw_rent.fact_contract_people
  WHERE
    sk_user > 0 AND is_last_contract = TRUE
  GROUP BY
    1
), agg_cpf AS (
  SELECT
    sk_personal_document,
    COUNT(DISTINCT sk_contract) AS contracts_created
  FROM dw_rent.fact_contract_people
  WHERE
    NOT sk_personal_document IS NULL
  GROUP BY
    1
), agg_user AS (
  SELECT
    sk_user,
    COUNT(sk_contract) AS contracts_created
  FROM dw_rent.fact_contract_people
  WHERE
    sk_user > 0
  GROUP BY
    1
), latest_contract_people AS (
  SELECT
    fcp.sk_personal_document,
    DATEDIFF(YEAR, dcp.dt_birth, CURRENT_DATE) AS age,
    dcp.gender,
    dcp.marital_status,
    dcp.has_ongoing_contract,
    fcp.contract_role AS last_contract_role,
    fcp.is_contract_user AS is_contract_user,
    fcp.is_first_contract = TRUE AS is_first_contract,
    fcp.is_living,
    ac.contracts_created
  FROM clean_contract_people AS ccp
  INNER JOIN dw_rent.fact_contract_people AS fcp
    ON fcp.sk_contract_person = ccp.sk_max_contract_person
  INNER JOIN dw_rent.dim_contract_person AS dcp
    ON dcp.sk_contract_person = fcp.sk_contract_person
  INNER JOIN agg_cpf AS ac
    ON ac.sk_personal_document = fcp.sk_personal_document
  WHERE
    NOT fcp.sk_personal_document IS NULL AND sk_user = -1 AND is_last_contract = TRUE
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10
), latest_contract_users AS (
  SELECT
    fcp.sk_user,
    DATEDIFF(YEAR, dcp.dt_birth, CURRENT_DATE) AS age,
    dcp.gender,
    dcp.marital_status,
    dcp.has_ongoing_contract,
    fcp.contract_role AS last_contract_role,
    fcp.is_contract_user AS is_contract_user,
    fcp.is_first_contract = TRUE AS is_first_contract,
    fcp.is_living,
    au.contracts_created
  FROM clean_contract_users AS ccu
  INNER JOIN dw_rent.fact_contract_people AS fcp
    ON fcp.sk_contract_person = ccu.sk_max_contract_person
  INNER JOIN dw_rent.dim_contract_person AS dcp
    ON dcp.sk_contract_person = fcp.sk_contract_person
  INNER JOIN agg_user AS au
    ON au.sk_user = fcp.sk_user
  WHERE
    fcp.sk_user > 0 AND is_last_contract = TRUE
  GROUP BY
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10
), user_roles AS (
  SELECT
    u.sk_user,
    DATEDIFF(YEAR, u.data_nascimento, CURRENT_DATE) AS age,
    CASE
      WHEN u.sexo = 'Masculino'
      THEN 'masculine'
      WHEN u.sexo = 'Feminino'
      THEN 'feminine'
    END AS gender,
    u.dados_agente_id > 0 AS is_agent,
    u.is_rent_agent,
    u.is_sale_agent,
    u.dados_fotografo_id > 0 AS is_photographer,
    u.dados_vendedor_id > 0 AS is_salesperson,
    u.dados_afiliado_id > 0 AS is_affiliate,
    CASE
      WHEN u.flg_doorman_affiliate = 0
      THEN FALSE
      WHEN u.flg_doorman_affiliate = 1
      THEN TRUE
    END AS is_doorman,
    CASE WHEN u.tem_imovel = '0' THEN FALSE WHEN u.tem_imovel = '1' THEN TRUE END AS has_houses,
    CASE
      WHEN u.tem_app_inquilino = '0'
      THEN FALSE
      WHEN u.tem_app_inquilino = '1'
      THEN TRUE
    END AS has_tenant_app,
    au.contracts_created
  FROM dw_public.dim_user AS u
  INNER JOIN agg_user AS au
    ON au.sk_user = u.sk_user
)
SELECT
  COALESCE(CAST(c.sk_user AS STRING), c.sk_personal_document) AS id_customer_context,
  c.sk_user,
  c.name,
  c.email,
  COALESCE(u.cpf, c.sk_personal_document) AS sk_personal_document, /* recover cpf info for users */
  COALESCE(ur.age, lu.age, cp.age) AS age,
  COALESCE(ur.gender, lu.gender, cp.gender) AS gender,
  COALESCE(cp.marital_status, lu.marital_status) AS marital_status,
  COALESCE(ur.has_houses, FALSE) AS has_houses,
  COALESCE(ur.has_tenant_app, FALSE) AS has_tenant_app,
  COALESCE(lu.last_contract_role, cp.last_contract_role, 'none') AS last_contract_role,
  COALESCE(lu.is_contract_user, cp.is_contract_user, FALSE) AS is_contract_user,
  COALESCE(lu.is_first_contract, cp.is_first_contract, FALSE) AS is_first_contract,
  COALESCE(lu.is_living, cp.is_living, FALSE) AS has_lived,
  COALESCE(lu.has_ongoing_contract, cp.has_ongoing_contract, FALSE) AS has_ongoing_contract,
  COALESCE(ur.contracts_created, lu.contracts_created, cp.contracts_created, 0) AS contracts_created,
  COALESCE(ur.is_agent, FALSE) AS is_agent,
  COALESCE(ur.is_rent_agent, FALSE) AS is_rent_agent,
  COALESCE(ur.is_sale_agent, FALSE) AS is_sale_agent,
  COALESCE(ur.is_photographer, FALSE) AS is_photographer,
  COALESCE(ur.is_salesperson, FALSE) AS is_salesperson,
  COALESCE(ur.is_affiliate, FALSE) AS is_affiliate,
  COALESCE(ur.is_doorman, FALSE) AS is_doorman
FROM customers AS c
LEFT JOIN latest_contract_people AS cp
  ON c.sk_personal_document = cp.sk_personal_document
LEFT JOIN latest_contract_users AS lu
  ON c.sk_user = lu.sk_user
LEFT JOIN user_roles AS ur
  ON c.sk_user = ur.sk_user
LEFT JOIN dw_public.dim_user AS u
  ON c.sk_user = u.sk_user