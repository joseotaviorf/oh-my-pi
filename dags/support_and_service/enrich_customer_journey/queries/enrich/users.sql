-- this table is temporary and should be replaced by BIC and other efforts related to datalake_user
WITH iq_post AS (
  SELECT DISTINCT
    du.sk_user
  FROM
    dw_public.dim_user AS du
  LEFT JOIN
    datalake_user.persona_type AS pt
       ON pt.id_user = du.sk_user
       AND pt.client_type = 'property_owner'
       AND pt.year = {year}
       AND pt.month = {month}
       AND pt.day = {day}
  WHERE
    pt.id_user IS NULL
    AND du.active = 1
    AND du.tem_contrato_ativo = 1
    AND du.inquilino = 1
    AND du.tem_imovel = 0
    AND du.is_rent_agent IS NULL
    AND du.is_sale_agent IS NULL
    AND du.dados_agente_id IS NULL
    AND du.dados_fotografo_id IS NULL
    AND du.dados_vendedor_id IS NULL
    AND du.dados_afiliado_id IS NULL
),
iq_pre AS (
  SELECT DISTINCT
    du.sk_user
  FROM
    dw_public.dim_user AS du
  LEFT JOIN
    datalake_user.persona_type AS pt
       ON pt.id_user = du.sk_user
       AND pt.client_type = 'property_owner'
       AND pt.year = {year}
       AND pt.month = {month}
       AND pt.day = {day}
  LEFT JOIN
    iq_post AS ip
      ON ip.sk_user = du.sk_user
  WHERE
    pt.id_user IS NULL
    AND ip.sk_user IS NULL
    AND du.visits_booked >= 1
    AND du.inquilino = 1
    AND du.tem_imovel = 0
    AND du.is_rent_agent IS NULL
    AND du.is_sale_agent IS NULL
    AND du.dados_agente_id IS NULL
    AND du.dados_fotografo_id IS NULL
    AND du.dados_vendedor_id IS NULL
    AND du.dados_afiliado_id IS NULL
    AND du.first_signed_contract IS NULL
),
pp_post AS (
  SELECT DISTINCT
      du.sk_user
    FROM
      dw_public.dim_user AS du
    INNER JOIN
      datalake_user.persona_type AS pt
        ON pt.id_user = du.sk_user
        AND pt.client_type = 'property_owner'
        AND pt.year = {year}
        AND pt.month = {month}
        AND pt.day = {day}
    WHERE
      du.active = 1
      AND du.tem_contrato_ativo = 1
      AND du.tem_imovel = 1
),
pp_pre AS (
  SELECT
      du.sk_user
    FROM
      dw_public.dim_user AS du
    INNER JOIN
      datalake_user.persona_type AS pt
        ON pt.id_user = du.sk_user
        AND pt.client_type = 'property_owner'
        AND pt.year = {year}
        AND pt.month = {month}
        AND pt.day = {day}
    LEFT JOIN
      pp_post AS ppp
        ON ppp.sk_user = du.sk_user
    WHERE
      ppp.sk_user IS NULL
      AND du.visits_booked >= 1
      AND du.tem_imovel = 1
      AND du.first_signed_contract IS NULL
)
SELECT
  sk_user AS id_user,
  "tenant_post_contract"  AS journey_step
FROM
  iq_post
UNION ALL
SELECT
  sk_user AS id_user,
  "tenant_pre_contract"  AS journey_step
FROM
  iq_pre
UNION ALL
SELECT
  sk_user AS id_user,
  "landlord_post_contract"  AS journey_step
FROM
  pp_post
UNION ALL
SELECT
  sk_user AS id_user,
  "landlord_pre_contract"  AS journey_step
FROM
  pp_pre
