WITH conversion_tb AS (
  SELECT 
    p.sk_supply_lead, 
    l3p.business_context,
    l3p.id_lead_3p AS id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'conversion_q2aq' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    '-1' AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM datalake_supply_flows_migrate.prospects_3p AS p
  JOIN datalake_supply_flows_migrate.landing_3p AS l3p
    ON (p.id_lead = l3p.id_lead_3p)
    AND (p.business_context = l3p.business_context)
    AND (l3p.growth_status = 'AV_QUALIFIED')
    AND (l3p.aux_round_number = 1)
  WHERE DATE(l3p.ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}') -- CARREGO SOMENTE EVENTOS QUE ACONTECERAM NA JANELA
),
drop_tb AS (
  -- FAÇO UM LEFT ANTI JOIN PARA RETIRAR TODOS QUE CONVERTERAM
  SELECT l.aux_hash
  FROM datalake_supply_flows_migrate.prospects_3p AS l
  LEFT ANTI JOIN conversion_tb AS c
      ON (l.id_lead = c.id_lead)
      AND (l.business_context = c.business_context)
  GROUP BY ALL
),
discards_events AS (
  -- PEGO TODOS OS EVENTOS DE DESCARTE BASEADO NA HASH E QUE ESTÃO DENTRO DA JANELA
  -- SEMPRE A PRIMEIRA RODADA
  SELECT *
  FROM datalake_supply_flows_migrate.landing_3p AS l3p
  WHERE aux_round_number = 1
    AND aux_hash IN (SELECT * FROM drop_tb)
    AND DATE(ts_event) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}') -- CARREGO SOMENTE EVENTOS QUE ACONTECERAM NA JANELA 
    AND growth_status = 'QUALIFIED'
  QUALIFY ROW_NUMBER() OVER (PARTITION BY l3p.id_lead_3p ORDER BY l3p.ts_event) = 1 
),
final_tb AS (
  -- AQUI CRIO A TABELA DE DESCARTES E JUNTO COM A DE CONVERSÃO
  SELECT 
    ls.sk_supply_lead, 
    l3p.business_context,
    ls.id_lead,
    l3p.id_region,
    l3p.id_house,
    -1 AS id_lead_ebdb,
    -1 AS id_referred_by,
    'drop_q2aq' AS business_event,
    l3p.growth_status AS funnel_step,
    2 AS funnel_level,
    '3P' AS supply_source,
    COALESCE(l3p.reason, -2) AS drop_step_reason,
    COALESCE(l3p.status, -1) AS aux_product_status,
    l3p.aux_hash,
    l3p.ts_event
  FROM datalake_supply_flows.leads_sks AS ls
  INNER JOIN discards_events AS l3p
      ON ls.id_lead = l3p.id_lead_3p
        AND (ls.source = '3P')
  UNION ALL
  SELECT *
  FROM conversion_tb
)

SELECT 
  *,
  NOW() AS ts_load,
  YEAR(ts_event) AS year,
  MONTH(ts_event) AS month,
  DAY(ts_event) AS day
FROM final_tb