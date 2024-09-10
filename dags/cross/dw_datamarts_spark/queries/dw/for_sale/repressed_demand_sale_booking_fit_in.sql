-- Creating a table for each change in house's visit agenda
WITH house_available_hours AS (
  WITH imovel_aud AS (
    SELECT
        CAST(FROM_UNIXTIME(CAST(ure.ts_revision AS BIGINT)/1000) AS TIMESTAMP) AS date_time,
        hou.*
    FROM
      datalake_ebdb_clean.house_weekly_schedule_aud AS hou
    JOIN
      datalake_ebdb_clean.user_revision_entity AS ure
        ON hou.rev = ure.id
    JOIN
      datalake_ebdb_clean.listing_business_context AS lbc
        ON hou.id_house = lbc.id_house
        AND lbc.business_context = 'SALE'
  ),
  house_available AS (
    SELECT
      id_house,
      date_time AS available_started_date,
      LEAD(date_time) OVER(PARTITION BY id_house, weekday ORDER BY rev) AS available_ended_date,
      weekday AS day_of_week,
      is_available_between_08_and_09 AS hours_available_08to09,
      is_available_between_09_and_10 AS hours_available_09to10,
      is_available_between_10_and_11 AS hours_available_10to11,
      is_available_between_11_and_12 AS hours_available_11to12,
      is_available_between_12_and_13 AS hours_available_12to13,
      is_available_between_13_and_14 AS hours_available_13to14,
      is_available_between_14_and_15 AS hours_available_14to15,
      is_available_between_15_and_16 AS hours_available_15to16,
      is_available_between_16_and_17 AS hours_available_16to17,
      is_available_between_17_and_18 AS hours_available_17to18,
      is_available_between_18_and_19 AS hours_available_18to19,
      is_available_between_19_and_20 AS hours_available_19to20
    FROM
      imovel_aud AS ia
  )
  SELECT
    id_house,
    CAST(REPLACE(CAST(DATE(available_started_date) AS STRING),'-','') AS BIGINT) AS sk_available_started_date,
    CAST(REPLACE(CAST(DATE(available_ended_date) AS STRING),'-','') AS BIGINT) AS sk_available_ended_date,
    available_started_date,
    available_ended_date,
    day_of_week,
    hours_available_08to09,
    hours_available_09to10,
    hours_available_10to11,
    hours_available_11to12,
    hours_available_12to13,
    hours_available_13to14,
    hours_available_14to15,
    hours_available_15to16,
    hours_available_16to17,
    hours_available_17to18,
    hours_available_18to19,
    hours_available_19to20
  FROM
    house_available
),
-- Creating a date_series table for weeks between -10W AND +1W
date_series AS (
  SELECT
    date,
    week_day,
    weekday_name,
    week_start,
    CASE
        WHEN week_day = '6' THEN 'Saturday'
        WHEN week_day = '0' THEN 'Sunday'
        ELSE 'Weekday'
    END AS week_day_type
  FROM
    dw_public.dim_date AS dd
  WHERE
    date >= DATE_TRUNC('week', CURRENT_DATE) - INTERVAL '10 week' AND week_start <= DATE_TRUNC('week', CURRENT_DATE) + INTERVAL '1 week'
    AND date IS NOT NULL
),
-- Creating a region table with all sales neighborhood
regions AS (
  SELECT DISTINCT
    fv.sk_region AS region_id,
    dr.region_code,
    dr.city_group,
    dr.city_name,
    dr.name
  FROM
    dw_sale.fact_visits AS fv
  LEFT JOIN
    dw_public.dim_region AS dr
        ON dr.id = fv.sk_region
  WHERE
    dr.region_code IS NOT NULL
),
-- Creating a slot_series table from 0 to 99
slot_series AS (
  SELECT
    EXPLODE(SEQUENCE(0, 99)) AS slot
),
-- Creating a dimension table, unifying date_series, region and slot_series
dimensions AS (
  SELECT
    CAST(r.region_id AS BIGINT) AS region_id,
    r.region_code,
    r.city_name,
    r.city_group AS city_group,
    r.name,
    ds.date,
    ds.week_start,
    ss.slot,
    CASE
      WHEN ss.slot BETWEEN 0 AND 3 THEN 8
      WHEN ss.slot BETWEEN 4 AND 7 THEN 9
      WHEN ss.slot BETWEEN 8 AND 11 THEN 10
      WHEN ss.slot BETWEEN 12 AND 15 THEN 11
      WHEN ss.slot BETWEEN 16 AND 19 THEN 12
      WHEN ss.slot BETWEEN 20 AND 23 THEN 13
      WHEN ss.slot BETWEEN 24 AND 27 THEN 14
      WHEN ss.slot BETWEEN 28 AND 31 THEN 15
      WHEN ss.slot BETWEEN 32 AND 35 THEN 16
      WHEN ss.slot BETWEEN 36 AND 39 THEN 17
      WHEN ss.slot BETWEEN 40 AND 43 THEN 18
      WHEN ss.slot BETWEEN 44 AND 47 THEN 19
      WHEN ss.slot BETWEEN 48 AND 51 THEN 20
      WHEN ss.slot BETWEEN 52 AND 55 THEN 21
      WHEN ss.slot BETWEEN 56 AND 59 THEN 22
      WHEN ss.slot BETWEEN 60 AND 63 THEN 23
    END AS hour,
    CASE
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 0 AND 3 THEN '1) Weekday 8-9h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 4 AND 19 THEN '2) Weekday 9-13h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 20 AND 31 THEN '3) Weekday 13-16h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 32 AND 35 THEN '4) Weekday 16-17h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 36 AND 63 THEN '5) Extended hours'
      WHEN ds.week_day = 6 THEN '6) Saturday all hours'
      WHEN ds.week_day = 0 THEN '7) Sunday all hours'
    END AS faixa
  FROM
    regions AS r
  CROSS JOIN
    date_series AS ds
  CROSS JOIN
    slot_series AS ss
),
-- Creating a booking table for all sales bookings created after weeks >= -10W
encaixe_to_booking AS (
  SELECT DISTINCT
    id_visitor AS user_id,
    id_property AS house_id
  FROM
    dw_public.dim_booking
  WHERE
    type = 'Visita'
    AND visit_intent = 'SALE'
    AND dt_scheduling >= DATE_TRUNC('week', CURRENT_DATE) - INTERVAL '10 week'
),
-- Creating a booking table for realized, confirmed or cancelled rent bookings created after weeks >= -10W
booking_for_rent AS (
  SELECT DISTINCT
    id_visitor AS user_id,
    id_property AS house_id,
    slot_dia AS slot_dia,
    dt_scheduling,
    DATE(dt_scheduling) AS visit_date,
    visit_intent,
    status
  FROM
    dw_public.dim_booking
  WHERE
    type = 'Visita'
    AND visit_intent = 'RENT'
    AND id_visitor IS NOT NULL
    AND dt_scheduling >= DATE_TRUNC('week', CURRENT_DATE) - INTERVAL '10 week'
    AND (status = 'Realizado' OR status = 'Marcado' OR
        (status = 'Cancelado' AND DATE(dt_scheduling) = DATE(dt_cancel)))
),
-- Creating a fitting request table for all fitting requested on site created after weeks >= -10W
visit_hoursalert_confirmed AS (
  SELECT
    CAST(id_user AS BIGINT) AS user_id,
    ep_house_id AS house_id,
    ep_alert_slot_from AS alert_slot_from,
    ep_alert_slot_to AS alert_slot_to,
    dt_alert_target AS target_date,
    ts_event AS event_date
  FROM
    datalake_amplitude_clean.170698_visit_hoursalert_confirmed_events
  WHERE
    TRIM(ep_business_context) = 'sale'
    AND ep_house_id IS NOT NULL
    AND id_user <> ''
    AND ts_event >= DATE_TRUNC('week', current_date) - interval '10 week'
 UNION ALL
SELECT 
  id_visitor AS user_id,
  id_house AS house_id,
  begin_slot AS alert_slot_from,
  end_slot AS alert_slot_to,
  dt_visit AS target_date,
  ts_created AS event_date
FROM 
  datalake_ebdb_clean.visit_fitting
WHERE
  business_context = 'SALE'),
-- Business rule to confirm if a fitting request has a booking created after request date, if so the fitting was realized
encaixes_raw AS (
  SELECT
    evt.event_date,
    evt.user_id,
    evt.house_id,
    evt.target_date,
    evt.alert_slot_from,
    evt.alert_slot_to,
    CASE WHEN etb.user_id IS NOT NULL THEN 1 ELSE 0 END AS encaixe_realizado,
    RANK() OVER(PARTITION BY evt.user_id, evt.house_id ORDER BY evt.event_date DESC) AS rank_enc
  FROM
    visit_hoursalert_confirmed AS evt
  LEFT JOIN
    encaixe_to_booking AS etb
      ON etb.user_id = evt.user_id
      AND etb.house_id = evt.house_id
),
-- Business rule to split the fitting request into each requested time slot
encaixes_temp AS (
  SELECT DISTINCT
    enc.user_id,
    enc.house_id,
    h.id_region AS region_id,
    enc.event_date,
    enc.target_date,
    ss.slot,
    enc.encaixe_realizado,
    1.0/CAST(COUNT(slot) OVER(PARTITION BY enc.user_id,enc.house_id, enc.target_date) AS FLOAT) AS slot_share_encaixe
  FROM
    encaixes_raw AS enc
  JOIN
    slot_series AS ss
      ON ss.slot BETWEEN enc.alert_slot_from AND enc.alert_slot_to
  JOIN
    datalake_ebdb_clean.house AS h
      ON h.id = enc.house_id
  WHERE
    enc.rank_enc = 1
    AND enc.user_id IS NOT NULL
    AND h.id_region IS NOT NULL
    AND enc.target_date IS NOT NULL
),
blocked_houses_aux AS (
  SELECT
    vs.id_house AS house_id,
    vs.status,
    CAST(FROM_UNIXTIME(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP) AS init,
    COALESCE(
      LEAD(CAST(FROM_UNIXTIME(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP)) OVER(
        PARTITION BY
          vs.id_house
        ORDER BY
          r.ts_revision
        ),
        CURRENT_DATE
      ) AS `end`
  FROM
    datalake_ebdb_clean.house_visit_status_aud AS vs
  JOIN
    datalake_ebdb_clean.user_revision_entity AS r
      ON vs.rev = r.id
      AND mod_status = true
  JOIN
    datalake_ebdb_clean.listing_business_context AS lbc
      ON vs.id_house = lbc.id_house
      AND lbc.business_context = 'SALE'
),
-- Creating a blocked house table. Filter status=BLOCKED after define 'init' AND 'end'
blocked_houses AS (
  SELECT *
  FROM
    blocked_houses_aux
  WHERE
    status = 'BLOCKED'
),
suspended_houses_aux AS (
  SELECT
    h.id_house AS house_id,
    h.status,
    CAST(FROM_UNIXTIME(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP) AS init,
    COALESCE(LEAD(CAST(FROM_UNIXTIME(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP)) OVER(PARTITION BY h.id_house ORDER BY r.ts_revision), current_date) AS `end`
  FROM
    datalake_ebdb_clean.house_aud AS h
  JOIN
    datalake_ebdb_clean.user_revision_entity AS r
      ON h.rev = r.id
      AND h.mod_status = true
  JOIN
    datalake_ebdb_clean.listing_business_context AS lbc
      ON h.id_house = lbc.id_house
      AND lbc.business_context = 'SALE'
),
-- Creating a suspended house table. Filter status=suspenso after define 'init' AND 'end'
suspended_houses AS (
  SELECT *
  FROM
    suspended_houses_aux
  WHERE
    status = 'suspenso'
),
 -- Canceled bookings that are considered repressed demand
cant_find_another_agent AS (
	SELECT DISTINCT
    id_visitor AS user_id,
    id_property AS house_id,
    CAST(slot_dia AS BIGINT) AS slot_dia,
    dt_scheduling,
    DATE(dt_scheduling) AS visit_date,
    status
  FROM
    dw_public.dim_booking
  WHERE
      type = 'Visita'
      AND visit_intent = 'SALE'
      AND status = 'Cancelado'
      AND cancellation_reason = 'CANCELED_CANT_FIND_ANOTHER_AGENT'
      AND DATE(dt_scheduling) >= DATE_TRUNC('week', CURRENT_DATE) - INTERVAL '10 week'
),
-- Business rule to identify the reason why some fitting request was or wasn't realized
encaixes_clean AS (
  SELECT
    t.region_id,
    MAX(t.house_id) AS house_id,
    t.user_id,
    t.event_date,
    t.target_date,
    t.slot,
    t.slot_share_encaixe,
    CASE WHEN t.encaixe_realizado = 0 AND (t.event_date BETWEEN bh.init AND bh.`end`) AND bh.status = 'BLOCKED' THEN t.slot_share_encaixe END AS slot_share_nao_realizados_por_bloqueio,
    CASE WHEN t.encaixe_realizado = 0 AND (t.event_date BETWEEN sh.init AND sh.`end`) AND sh.status = 'suspenso' THEN t.slot_share_encaixe END AS slot_share_nao_realizados_por_suspensao,
    CASE WHEN
      t.encaixe_realizado = 0 AND (((t.event_date BETWEEN sh.init AND sh.`end`) AND sh.status = 'suspenso') OR ((t.event_date BETWEEN bh.init AND bh.`end`)and bh.status = 'BLOCKED')) THEN t.slot_share_encaixe
    END AS slot_share_nao_realizados_por_bloqueio_suspensao,
    CASE WHEN t.encaixe_realizado = 1 THEN t.slot_share_encaixe END AS slot_share_encaixe_realizado,
    CASE WHEN t.encaixe_realizado = 0 THEN t.slot_share_encaixe END AS slot_share_encaixe_nao_realizado,
    CASE WHEN t.encaixe_realizado = 0
      AND ((t.slot BETWEEN 0 AND 3 AND hs.hours_available_08to09 = false)
      OR (t.slot BETWEEN 4 AND 7 AND hs.hours_available_09to10 = false)
      OR (t.slot BETWEEN 8 AND 11 AND hs.hours_available_10to11 = false)
      OR (t.slot BETWEEN 12 AND 15 AND hs.hours_available_11to12 = false)
      OR (t.slot BETWEEN 16 AND 19 AND hs.hours_available_12to13 = false)
      OR (t.slot BETWEEN 20 AND 23 AND hs.hours_available_13to14 = false)
      OR (t.slot BETWEEN 24 AND 27 AND hs.hours_available_14to15 = false)
      OR (t.slot BETWEEN 28 AND 31 AND hs.hours_available_15to16 = false)
      OR (t.slot BETWEEN 32 AND 35 AND hs.hours_available_16to17 = false)
      OR (t.slot BETWEEN 36 AND 39 AND hs.hours_available_17to18 = false)
      OR (t.slot BETWEEN 40 AND 43 AND hs.hours_available_18to19 = false))
    THEN t.slot_share_encaixe END AS slot_share_nao_realizados_por_agenda,
    CASE WHEN t.encaixe_realizado = 0
      AND (((t.event_date BETWEEN sh.init AND sh.`end`) AND sh.status = 'suspenso') OR ((t.event_date BETWEEN bh.init AND bh.`end`) AND bh.status = 'BLOCKED')
      OR ((t.slot BETWEEN 0 AND 3 AND hs.hours_available_08to09 = false)
      OR (t.slot BETWEEN 4 AND 7 AND hs.hours_available_08to09 = false)
      OR (t.slot BETWEEN 8 AND 11 AND hs.hours_available_10to11 = false)
      OR (t.slot BETWEEN 12 AND 15 AND hs.hours_available_11to12 = false)
      OR (t.slot BETWEEN 16 AND 19 AND hs.hours_available_12to13 = false)
      OR (t.slot BETWEEN 20 AND 23 AND hs.hours_available_13to14 = false)
      OR (t.slot BETWEEN 24 AND 27 AND hs.hours_available_14to15 = false)
      OR (t.slot BETWEEN 28 AND 31 AND hs.hours_available_15to16 = false)
      OR (t.slot BETWEEN 32 AND 35 AND hs.hours_available_16to17 = false)
      OR (t.slot BETWEEN 36 AND 39 AND hs.hours_available_17to18 = false)
      OR (t.slot BETWEEN 40 AND 43 AND hs.hours_available_18to19 = false)))
    THEN t.slot_share_encaixe END AS slot_share_nao_realizados_por_bloqueio_suspensao_agenda,
    CASE
      WHEN t.encaixe_realizado = 1 AND cfaa.status = 'Cancelado' THEN t.slot_share_encaixe
    END AS slot_share_encaixe_nao_realizado_cant_find_another_agent,
    CAST(hs.hours_available_08to09 AS BIGINT) + CAST(hs.hours_available_09to10 AS BIGINT) + CAST(hs.hours_available_10to11 AS BIGINT) +
        CAST(hs.hours_available_11to12 AS BIGINT) + CAST(hs.hours_available_12to13 AS BIGINT) + CAST(hs.hours_available_13to14 AS BIGINT) +
        CAST(hs.hours_available_14to15 AS BIGINT) + CAST(hs.hours_available_15to16 AS BIGINT) + CAST(hs.hours_available_16to17 AS BIGINT) +
        CAST(hs.hours_available_17to18 AS BIGINT) + CAST(hs.hours_available_18to19 AS BIGINT) AS slots_disponiveis_target_date,
    CASE
      WHEN t.encaixe_realizado = 0 AND bfr.visit_intent = 'RENT' THEN t.slot_share_encaixe
      ELSE NULL
    END AS slot_share_ocupado_por_visita_rent
  FROM
    encaixes_temp AS t
  LEFT JOIN
    house_available_hours AS hs
      ON t.house_id = hs.id_house
      AND hs.day_of_week = EXTRACT(dow FROM t.target_date) - 1
      AND t.event_date BETWEEN hs.available_started_date AND COALESCE(hs.available_ended_date, (date_add(current_date, 2)))
  LEFT JOIN
    blocked_houses AS bh
      ON t.house_id = bh.house_id
      AND t.event_date BETWEEN bh.init AND bh.`end`
  LEFT JOIN
    suspended_houses AS sh
      ON t.house_id = sh.house_id
      AND t.event_date BETWEEN sh.init AND sh.`end`
  LEFT JOIN
    booking_for_rent AS bfr
      ON t.house_id = bfr.house_id
      AND t.user_id = bfr.user_id
      AND t.target_date = bfr.visit_date
      AND t.slot = bfr.slot_dia
  LEFT JOIN
    cant_find_another_agent AS cfaa
      ON CAST(t.house_id AS BIGINT) = CAST(cfaa.house_id AS BIGINT)
      AND t.target_date = cfaa.visit_date
      AND t.slot = cfaa.slot_dia
  GROUP BY
    1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
),
encaixes_agg AS (
  SELECT
    region_id,
    event_date,
    target_date,
    slot,
    user_id,
    house_id,
    SUM(slot_share_encaixe) AS share_encaixes_total,
    SUM(COALESCE(slot_share_encaixe_realizado,0) - COALESCE(slot_share_encaixe_nao_realizado_cant_find_another_agent,0)) AS share_encaixes_realizados,
    SUM(COALESCE(slot_share_encaixe_nao_realizado,0) + COALESCE(slot_share_encaixe_nao_realizado_cant_find_another_agent,0)) AS share_encaixes_nao_realizados,
    SUM(slot_share_encaixe_nao_realizado_cant_find_another_agent) AS share_encaixes_nao_realizados_cant_find_another_agent,
    SUM(slot_share_nao_realizados_por_agenda) AS share_encaixes_nao_realizados_por_agenda,
    SUM(slot_share_nao_realizados_por_bloqueio) AS share_encaixes_nao_realizados_por_bloqueio,
    SUM(slot_share_nao_realizados_por_suspensao) AS share_encaixes_nao_realizados_por_suspensao,
    SUM(slot_share_nao_realizados_por_bloqueio_suspensao) AS share_encaixes_nao_realizados_por_bloqueio_suspensao,
    SUM(slot_share_nao_realizados_por_bloqueio_suspensao_agenda) AS share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
    SUM(CASE WHEN slots_disponiveis_target_date = 0 THEN slot_share_encaixe END) AS encaixes_em_imovel_sem_slot_disponivel_target_date,
    SUM(slot_share_ocupado_por_visita_rent) AS share_encaixes_nao_realizados_por_visita_rent,
    SUM(
      COALESCE(slot_share_encaixe_nao_realizado, 0) +
      COALESCE(slot_share_encaixe_nao_realizado_cant_find_another_agent, 0) -
      (COALESCE(slot_share_nao_realizados_por_bloqueio_suspensao_agenda, 0) +
      COALESCE(slot_share_ocupado_por_visita_rent,0))
    ) AS share_encaixes_nao_realizados_por_agent
  FROM
    encaixes_clean
  GROUP BY
    1,2,3,4,5,6
)
SELECT
    d.region_code,
    d.city_name,
    d.city_group,
    d.name AS neighborhood,
    enc.event_date,
    enc.target_date AS visit_date, -- TODO: future adjustment for this column
    d.week_start AS week_start,
    CAST(d.date AS TIMESTAMP) AS visit_hour,
    d.hour AS hour,
    d.faixa,
    enc.user_id AS user_id,
    enc.house_id AS house_id,
    enc.slot AS slot,
    enc.share_encaixes_total AS sum_encaixes_total,
    enc.share_encaixes_realizados AS sum_encaixes_realizados,
    enc.share_encaixes_nao_realizados AS sum_encaixes_nao_realizados,
    enc.share_encaixes_nao_realizados_cant_find_another_agent AS sum_encaixes_nao_realizados_cant_find_another_agent,
    enc.share_encaixes_nao_realizados_por_agenda AS sum_encaixes_nao_realizados_por_agenda,
    enc.share_encaixes_nao_realizados_por_bloqueio AS sum_encaixes_nao_realizados_por_bloqueio,
    enc.share_encaixes_nao_realizados_por_suspensao AS sum_encaixes_nao_realizados_por_suspensao,
    enc.share_encaixes_nao_realizados_por_bloqueio_suspensao AS sum_encaixes_nao_realizados_por_bloqueio_suspensao,
    enc.share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda AS sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
    enc.encaixes_em_imovel_sem_slot_disponivel_target_date AS sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
    enc.share_encaixes_nao_realizados_por_visita_rent AS sum_encaixes_nao_realizados_por_visita_rent,
    enc.share_encaixes_nao_realizados_por_agent AS sum_encaixes_nao_realizados_por_agent
FROM
    dimensions AS d
LEFT JOIN encaixes_agg AS enc
  ON enc.region_id = d.region_id
  AND enc.target_date = d.`date`
  AND enc.slot = d.slot
WHERE
  event_date IS NOT NULL
