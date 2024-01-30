/*
         * Demanda reprimida de visitas RENT discriminando imóveis com horário de agenda bloqueado
         */
SELECT
  region_code,
  city_name,
  city_group,
  CAST(SUBSTRING(date, 1, 10) AS DATE) AS date,
  CAST(SUBSTRING(week_start, 1, 10) AS DATE) AS week_start,
  CAST(slot AS INT) AS slot,
  CAST(hour AS INT) AS hour,
  faixa,
  CAST(sum_bookings AS INT) AS sum_bookings,
  CAST(sum_encaixes AS DOUBLE) AS sum_encaixes,
  CAST(sum_encaixes_realized AS DOUBLE) AS sum_encaixes_realized,
  CAST(sum_encaixes_not_realized AS DOUBLE) AS sum_encaixes_not_realized,
  CAST(sum_encaixes_nao_realizado_cant_find_another_agent AS DOUBLE) AS sum_encaixes_nao_realizado_cant_find_another_agent,
  CAST(sum_encaixes_nao_realizados_por_agenda AS DOUBLE) AS sum_encaixes_nao_realizados_por_agenda,
  CAST(sum_encaixes_nao_realizados_por_bloqueio AS DOUBLE) AS sum_encaixes_nao_realizados_por_bloqueio,
  CAST(sum_encaixes_nao_realizados_por_suspensao AS DOUBLE) AS sum_encaixes_nao_realizados_por_suspensao,
  CAST(sum_encaixes_nao_realizados_por_bloqueio_suspensao AS DOUBLE) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao,
  CAST(sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda AS DOUBLE) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
  CAST(sum_encaixes_em_imovel_sem_slot_disponivel_target_date AS DOUBLE) AS sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
  CAST(sum_encaixes_nao_realizados_por_agent AS DOUBLE) AS sum_encaixes_nao_realizados_por_agent,
  CAST(sum_encaixes_nao_realizados_por_visita_sale AS DOUBLE) AS sum_encaixes_nao_realizados_por_visita_sale
FROM dw_datamarts.repressed_demand