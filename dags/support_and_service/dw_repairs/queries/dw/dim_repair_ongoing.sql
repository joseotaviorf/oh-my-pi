WITH criticidade AS (
  SELECT
    rt.id_ticket,
    CASE
      WHEN CAST(custom_fields['Nova criticidade'] AS STRING) IS NOT NULL
        THEN CAST(custom_fields['Nova criticidade'] AS STRING)
      WHEN CAST(custom_fields['Criticidade'] AS STRING) IS NOT NULL
        THEN CAST(custom_fields['Criticidade'] AS STRING)
      WHEN rt.tags LIKE '%triagem_automatica_comum%' AND rt.tags LIKE '%resolve_iq_pp_autosservico_prestadorpp%'
        THEN 'comum_criticidade'
      WHEN rt.tags LIKE '%triagem_automatica_urgente%' AND rt.tags LIKE '%resolve_iq_pp_autosservico_prestadorpp%'
        THEN 'urgente_criticidade'
      WHEN rt.tags LIKE '%triagem_automatica_emergencial%' AND rt.tags LIKE '%resolve_iq_pp_autosservico_prestadorpp%'
        THEN 'emergencial_criticidade'
      WHEN CAST(rt.custom_fields['Classificação do atendimento (Tags)'] AS STRING) IS NOT NULL
        THEN CAST(rt.custom_fields['Classificação do atendimento (Tags)'] AS STRING)
    END AS criticidade
  FROM
    datalake_repairs.repair_tickets AS rt
),
status_fup AS (
  SELECT
    rrtnf.id_repair_request AS sk_repair_request,
    rrtnf.status AS status_fup_iq
  FROM
    datalake_repairs_clean.repair_request_tenant_negotiation_follow_up AS rrtnf
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rrtnf.id ORDER BY rrtnf.ts_updated DESC) = 1
),
repair_request AS (
  SELECT
    rr.id AS sk_repair_request,
    rr.owner_approval AS owner_approval
  FROM
    datalake_repairs_clean.repair_request AS rr
  QUALIFY
    ROW_NUMBER() OVER (PARTITION BY rr.id ORDER BY rr.ts_updated DESC) = 1

)

SELECT
    CAST(rt.id_ticket AS BIGINT) AS sk_ticket,
    CAST(rt.custom_fields['Classificação de Reparo 1'] AS STRING) AS repair_class,
    CAST(rt.custom_fields['Classificação de Reparo 2'] AS STRING) AS repair_type,
    CAST(rt.custom_fields['Classificação de Reparo 3'] AS STRING) AS repair_detailed,
    CAST(rt.custom_fields['Fluxo de execução dos reparos'] AS STRING) AS execution_flow,
    CASE
      WHEN c.criticidade LIKE '%emergencial%'
        THEN 'Emergencial'
      WHEN c.criticidade LIKE '%urgente%'
        THEN 'Urgente'
      WHEN c.criticidade LIKE '%comum%'
        THEN 'Comum'
      WHEN c.criticidade like '%benfeitoria%'
        THEN 'Benfeitoria'
      WHEN c.criticidade IS NULL
        THEN 'Sem Defeito'
      ELSE 'Outros'
    END AS criticality,
    IF(DATEDIFF(DAY, rt.entrance_date, cast(rt.ts_created_local AS DATE)) <= 40, 'ONB', 'ONG') AS contract_journey,
    rt.service_provider,
    rt.front_or_back AS created_front_or_back,
    sf.status_fup_iq,
    rr.owner_approval,
    NOW() AS ts_load
FROM
  datalake_repairs.repair_tickets AS rt
LEFT JOIN
  criticidade AS c
    ON c.id_ticket = rt.id_ticket
LEFT JOIN
  status_fup AS sf
    ON sf.sk_repair_request = rt.id_request
LEFT JOIN
  repair_request AS rr
    ON rr.sk_repair_request = rt.id_request
