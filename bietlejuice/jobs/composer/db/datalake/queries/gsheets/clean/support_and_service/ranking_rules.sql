SELECT
  CAST(grupo AS INT) AS id_group,
  caixa AS type,
  responsavel AS responsible,
  etapa_da_jornada AS journey_step,
  CAST(resolution_peso AS DOUBLE) AS resolution_weight,
  CAST(sla_peso AS DOUBLE) AS sla_weight,
  CAST(produtividade_peso AS DOUBLE) AS productivity_weight,
  CAST(csat_peso AS DOUBLE) AS csat_weight,
  CAST(indice_voltaria_a_fazer_negocio_peso AS DOUBLE) AS would_do_business_again_weight,
  CAST(ra_nota_peso AS DOUBLE) AS reclameaqui_note_weight,
  CAST(indice_solucao_peso AS DOUBLE) AS solution_rate_weight,
  CAST(total AS DOUBLE) AS total
FROM 
  datalake_gsheets_raw.ranking_rules