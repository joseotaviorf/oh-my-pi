/*
         * Demanda reprimida de visitas SALE a nível de solicitação de encaixe
         */
SELECT
  region_code,
  city_name,
  city_group,
  neighborhood,
  CAST(event_date AS TIMESTAMP) AS event_date,
  CAST(visit_date AS DATE) AS visit_date,
  CAST(week_start AS DATE) AS week_start,
  CAST(visit_hour AS TIMESTAMP) AS visit_hour,
  CAST(slot AS INT) AS slot,
  CAST(hour AS INT) AS hour,
  faixa,
  CAST(user_id AS INT) AS user_id,
  CAST(house_id AS INT) AS house_id,
  CAST(sum_encaixes_total AS DOUBLE) AS sum_encaixes_total,
  CAST(sum_encaixes_realizados AS DOUBLE) AS sum_encaixes_realizados,
  CAST(sum_encaixes_nao_realizados AS DOUBLE) AS sum_encaixes_nao_realizados,
  CAST(sum_encaixes_nao_realizados_cant_find_another_agent AS DOUBLE) AS sum_encaixes_nao_realizados_cant_find_another_agent,
  CAST(sum_encaixes_nao_realizados_por_agenda AS DOUBLE) AS sum_encaixes_nao_realizados_por_agenda,
  CAST(sum_encaixes_nao_realizados_por_bloqueio AS DOUBLE) AS sum_encaixes_nao_realizados_por_bloqueio,
  CAST(sum_encaixes_nao_realizados_por_suspensao AS DOUBLE) AS sum_encaixes_nao_realizados_por_suspensao,
  CAST(sum_encaixes_nao_realizados_por_bloqueio_suspensao AS DOUBLE) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao,
  CAST(sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda AS DOUBLE) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
  CAST(sum_encaixes_em_imovel_sem_slot_disponivel_target_date AS DOUBLE) AS sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
  CAST(sum_encaixes_nao_realizados_por_agent AS DOUBLE) AS sum_encaixes_nao_realizados_por_agent,
  CAST(sum_encaixes_nao_realizados_por_visita_rent AS DOUBLE) AS sum_encaixes_nao_realizados_por_visita_rent
FROM dw_datamarts.repressed_demand_sale_booking_fit_in