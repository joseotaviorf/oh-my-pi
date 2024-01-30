/*
         * Demanda reprimida de visitas SALE discriminando imóveis com horário de agenda bloqueado
         */
SELECT
  region_code,
  city_name,
  city_group,
  CAST(date AS DATE) AS date,
  CAST(week_start AS DATE) AS week_start,
  CAST(slot AS INT) AS slot,
  CAST(hour AS INT) AS hour,
  faixa,
  CAST(sum_bookings AS INT) AS sum_bookings,
  CAST(sum_encaixes AS FLOAT) AS sum_encaixes,
  CAST(sum_encaixes_realized AS FLOAT) AS sum_encaixes_realized,
  CAST(sum_encaixes_not_realized AS FLOAT) AS sum_encaixes_not_realized,
  CAST(sum_encaixes_nao_realizado_cant_find_another_agent AS FLOAT) AS sum_encaixes_nao_realizado_cant_find_another_agent,
  CAST(sum_encaixes_nao_realizados_por_agenda AS FLOAT) AS sum_encaixes_nao_realizados_por_agenda,
  CAST(sum_encaixes_nao_realizados_por_bloqueio AS FLOAT) AS sum_encaixes_nao_realizados_por_bloqueio,
  CAST(sum_encaixes_nao_realizados_por_suspensao AS FLOAT) AS sum_encaixes_nao_realizados_por_suspensao,
  CAST(sum_encaixes_nao_realizados_por_bloqueio_suspensao AS FLOAT) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao,
  CAST(sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda AS FLOAT) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
  CAST(sum_encaixes_em_imovel_sem_slot_disponivel_target_date AS FLOAT) AS sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
  CAST(sum_encaixes_nao_realizados_por_agent AS FLOAT) AS sum_encaixes_nao_realizados_por_agent,
  CAST(sum_encaixes_nao_realizados_por_visita_rent AS FLOAT) AS sum_encaixes_nao_realizados_por_visita_rent
FROM datamarts.repressed_demand_sale