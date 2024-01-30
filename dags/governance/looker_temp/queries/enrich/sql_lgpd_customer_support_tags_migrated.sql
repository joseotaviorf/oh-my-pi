WITH call_tickets AS (
  SELECT DISTINCT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    CASE
      WHEN tags LIKE '%cm_direito_dos_titulares%'
      THEN 'Casa Mineira'
      ELSE 'QuintoAndar'
    END AS empresa,
    tags
  FROM datalake_customer_support.call
  WHERE
    tags LIKE '%lgpd_acesso_aos_dados%'
    OR tags LIKE '%lgpd_anonimização__bloqueio_e_eliminação%'
    OR tags LIKE '%lgpd_confirmação_de_processamento%'
    OR tags LIKE '%lgpd_correção_de_dados%'
    OR tags LIKE '%lgpd_portabilidade%'
    OR tags LIKE '%lgpd_revisão_do_processamento_automático%'
    OR tags LIKE '%lgpd_revogação_do_consentimento%'
), chat_tickets AS (
  SELECT DISTINCT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    CASE
      WHEN tags LIKE '%cm_direito_dos_titulares%'
      THEN 'Casa Mineira'
      ELSE 'QuintoAndar'
    END AS empresa,
    tags
  FROM datalake_customer_support.chat
  WHERE
    tags LIKE '%lgpd_acesso_aos_dados%'
    OR tags LIKE '%lgpd_anonimização__bloqueio_e_eliminação%'
    OR tags LIKE '%lgpd_confirmação_de_processamento%'
    OR tags LIKE '%lgpd_correção_de_dados%'
    OR tags LIKE '%lgpd_portabilidade%'
    OR tags LIKE '%lgpd_revisão_do_processamento_automático%'
    OR tags LIKE '%lgpd_revogação_do_consentimento%'
), email_tickets AS (
  SELECT DISTINCT
    CAST(id_ticket AS BIGINT) AS sk_ticket,
    CASE
      WHEN tags LIKE '%cm_direito_dos_titulares%'
      THEN 'Casa Mineira'
      ELSE 'QuintoAndar'
    END AS empresa,
    tags
  FROM datalake_customer_support.email
  WHERE
    tags LIKE '%lgpd_acesso_aos_dados%'
    OR tags LIKE '%lgpd_anonimização__bloqueio_e_eliminação%'
    OR tags LIKE '%lgpd_confirmação_de_processamento%'
    OR tags LIKE '%lgpd_correção_de_dados%'
    OR tags LIKE '%lgpd_portabilidade%'
    OR tags LIKE '%lgpd_revisão_do_processamento_automático%'
    OR tags LIKE '%lgpd_revogação_do_consentimento%'
), all_tags AS (
  SELECT
    sk_ticket,
    SPLIT(tags, CONCAT('\\Q', ',')) AS lgpd_tags,
    empresa
  FROM call_tickets
  UNION ALL
  SELECT
    sk_ticket,
    SPLIT(tags, CONCAT('\\Q', ',')) AS lgpd_tags,
    empresa
  FROM email_tickets
  UNION ALL
  SELECT
    sk_ticket,
    SPLIT(tags, CONCAT('\\Q', ',')) AS lgpd_tags,
    empresa
  FROM chat_tickets
)
SELECT
  sk_ticket,
  empresa,
  REPLACE(REPLACE(SLICE(all_tags.lgpd_tags, CAST(n.rn AS INT), 1)[0], '[', ''), '"', '') AS tags
FROM all_tags
JOIN (
  SELECT
    ROW_NUMBER() OVER () AS rn
  FROM dw_public.dim_region
  LIMIT 100
) AS n
  ON n.rn < SIZE(all_tags.lgpd_tags)
WHERE
  REPLACE(REPLACE(SLICE(all_tags.lgpd_tags, CAST(n.rn AS INT), 1)[0], '[', ''), '"', '') IN ('lgpd_acesso_aos_dados', 'lgpd_anonimização__bloqueio_e_eliminação', 'lgpd_confirmação_de_processamento', 'lgpd_correção_de_dados', 'lgpd_portabilidade', 'lgpd_revisão_do_processamento_automático', 'lgpd_revogação_do_consentimento')