-- this table is temporary and should be replaced by BIC and other efforts related to datalake_user
WITH iq_post AS (
  SELECT DISTINCT
    id_user
  FROM
    datalake_user.tenant_user
  WHERE
    is_tenant_post_contract IS TRUE
    AND year = {year}
    AND month = {month}
    AND day = {day}
),
iq_pre AS (
  SELECT DISTINCT
    id_user
  FROM
    datalake_user.tenant_user
  WHERE
    is_tenant_pre_contract IS TRUE
    AND year = {year}
    AND month = {month}
    AND day = {day}
),
pp_post AS (
  SELECT DISTINCT
    pt.id_user
  FROM
    dw_public.dim_user AS du
  INNER JOIN
    datalake_user.persona_type AS pt
      ON pt.id_user = du.sk_user
      AND pt.client_type = 'landlord'
      AND pt.year = {year}
      AND pt.month = {month}
      AND pt.day = {day}
  WHERE
    (du.active = 1 OR du.tem_contrato_ativo = 1)
    AND du.tem_imovel = 1
),
pp_pre AS (
  SELECT
    pt.id_user
  FROM
    dw_public.dim_user AS du
  INNER JOIN
    datalake_user.persona_type AS pt
      ON pt.id_user = du.sk_user
      AND pt.client_type = 'landlord'
      AND pt.year = {year}
      AND pt.month = {month}
      AND pt.day = {day}
  LEFT JOIN
    pp_post AS ppp
      ON ppp.id_user = pt.id_user
  WHERE
    ppp.id_user IS NULL
    AND du.tem_imovel = 1
)
SELECT
  id_user,
  "tenant_post_contract"  AS journey_step
FROM
  iq_post
UNION ALL
SELECT
  id_user,
  "tenant_pre_contract"  AS journey_step
FROM
  iq_pre
UNION ALL
SELECT
  id_user,
  "landlord_post_contract"  AS journey_step
FROM
  pp_post
UNION ALL
SELECT
  id_user,
  "landlord_pre_contract"  AS journey_step
FROM
  pp_pre
