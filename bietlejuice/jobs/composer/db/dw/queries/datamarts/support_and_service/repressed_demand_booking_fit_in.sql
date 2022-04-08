WITH house_available_hours AS (
	WITH imovel_aud AS (
		SELECT
      CAST(from_unixtime(CAST(ts_revision AS BIGINT)/1000) AS TIMESTAMP) AS date_time,
			hou.*
		FROM 
      datalake_ebdb_clean_prod.house_weekly_schedule_aud hou
    JOIN 
      datalake_ebdb_clean_prod.user_revision_entity ure
        ON hou.rev = ure.id
	),
  house_available as (
		SELECT 
      ia.id_house,
      ia.date_time AS available_started_date,
      LEAD(date_time) OVER(PARTITION BY id_house, weekday ORDER BY rev) AS available_ended_date,
      ia.weekday AS day_of_week,
      ia.is_available_between_08_and_09 AS hours_available_08to09,
      ia.is_available_between_09_and_10 AS hours_available_09to10,
      ia.is_available_between_10_and_11 AS hours_available_10to11,
      ia.is_available_between_11_and_12 AS hours_available_11to12,
      ia.is_available_between_12_and_13 AS hours_available_12to13,
      ia.is_available_between_13_and_14 AS hours_available_13to14,
      ia.is_available_between_14_and_15 AS hours_available_14to15,
      ia.is_available_between_15_and_16 AS hours_available_15to16,
      ia.is_available_between_16_and_17 AS hours_available_16to17,
      ia.is_available_between_17_and_18 AS hours_available_17to18,
      ia.is_available_between_18_and_19 AS hours_available_18to19,
      ia.is_available_between_19_and_20 AS hours_available_19to20
    FROM 
      imovel_aud ia
	)
  SELECT 
    ha.id_house,
    CAST(REPLACE(CAST(DATE(available_started_date) AS VARCHAR),'-','') AS BIGINT) AS sk_available_started_date,
		CAST(REPLACE(CAST(DATE(available_ended_date) AS VARCHAR),'-','') AS BIGINT) AS sk_available_ended_date,
    ha.available_started_date,
    ha.available_ended_date,
    ha.day_of_week,
    ha.hours_available_08to09,
    ha.hours_available_09to10,
    ha.hours_available_10to11,
    ha.hours_available_11to12,
    ha.hours_available_12to13,
    ha.hours_available_13to14,
    ha.hours_available_14to15,
    ha.hours_available_15to16,
    ha.hours_available_16to17,
    ha.hours_available_17to18,
    ha.hours_available_18to19,
    ha.hours_available_19to20
  FROM 
    house_available ha
),
date_series AS (
  SELECT
    dd.date AS date,
    week_day,
    weekday_name,
    week_start,
    CASE
        WHEN week_day = '6' THEN 'Saturday'
        WHEN week_day = '0' THEN 'Sunday' 
        ELSE 'Weekday'
    END AS week_day_type
  FROM
    public.dim_date dd
  WHERE 
    dd.date >= current_date - interval '45 days' 
    AND week_start <= current_date - interval '1' DAY
    AND dd.date IS NOT NULL
),
regions AS (
  SELECT DISTINCT 
    dr.id AS region_id,
    dr.region_code,
    dr.city_group,
    dr.city_name
  FROM
    public.dim_region dr
  WHERE
    dr.region_code != '-1'
),
slot_series AS (
	WITH slot_0_9 AS (
    SELECT 0 AS slot
    UNION ALL SELECT 1 AS slot
    UNION ALL SELECT 2 AS slot
    UNION ALL SELECT 3 AS slot
    UNION ALL SELECT 4 AS slot
    UNION ALL SELECT 5 AS slot
    UNION ALL SELECT 6 AS slot
    UNION ALL SELECT 7 AS slot
    UNION ALL SELECT 8 AS slot
    UNION ALL SELECT 9 AS slot
  )
  SELECT 
    a.slot + b.slot * 10 AS slot
  FROM 
    slot_0_9 a, slot_0_9 b
),
dimensions AS (
  SELECT
    r.region_id,
    r.region_code,
    r.city_name,
    r.city_group AS city_group,
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
    END AS hour,
    CASE 
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 0 AND 3 THEN '1) Weekday 8-9h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 4 AND 19 THEN '2) Weekday 9-13h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 20 AND 31 THEN '3) Weekday 13-16h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 32 AND 35 THEN '4) Weekday 16-17h'
      WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 36 AND 43 THEN '5) Extended hours'
      WHEN ds.week_day = 6 THEN '6) Saturday all hours'
      WHEN ds.week_day = 0 THEN '7) Sunday all hours'
    END AS faixa
  FROM
    regions r
  CROSS JOIN 
    date_series ds
  CROSS JOIN 
    slot_series ss
),
encaixe_to_booking AS (
  SELECT DISTINCT 
    id_visitor AS user_id,
    id_property AS house_id
  FROM
    public.dim_booking
  WHERE
    type = 'Visita'
    AND visit_intent = 'RENT'
    AND dt_scheduling >= current_date - interval '55 days'
),
booking_for_sale AS (
	SELECT DISTINCT
		id_visitor AS user_id,
    id_property AS house_id,
    slot_dia,
    dt_scheduling,
    DATE(dt_scheduling) AS visit_date,
    visit_intent,
    status
	FROM 
    public.dim_booking
	WHERE 
    type = 'Visita'
		AND visit_intent = 'SALE'
		AND id_visitor IS NOT NULL
		AND dt_scheduling >= current_date - interval '55 days'
		AND (
          status = 'Realizado' 
          OR status = 'Marcado' 
          OR (status = 'Cancelado' AND DATE(dt_scheduling) = DATE(dt_cancel))
        )
),
visit_hoursalert_confirmed AS (
    SELECT
        TRIM(event_type) AS event,
        ts_event AS event_date,
        CAST(id_user AS BIGINT) AS user_id,
        CAST(json_extract_path_text(event_properties,'house_id') AS BIGINT) AS house_id,
        COALESCE(json_extract_path_text(event_properties,'alert_target_date'),'') AS target_date_raw,
        CASE
            WHEN target_date_raw LIKE '__, __ ___ ____' THEN TO_DATE(target_date_raw, 'XX, DD Mon YYYY')
            WHEN target_date_raw LIKE '____-__-__' THEN TO_DATE(target_date_raw, 'YYYY-MM-DD')
            ELSE NULL
        END AS target_date,
        COALESCE(CAST(NULLIF(json_extract_path_text(event_properties,'alert_slot_from'), '') AS BIGINT), -1) AS alert_slot_from,
        COALESCE(CAST(NULLIF(json_extract_path_text(event_properties,'alert_slot_to'), '') AS BIGINT), -1) AS alert_slot_to
    FROM
        datalake_amplitude_clean_prod.events
    WHERE
        TRIM(event_type) = 'visit_hoursalert_confirmed'
        AND json_extract_path_text(event_properties, 'business_context') = 'rent'
        AND json_extract_path_text(event_properties, 'house_id') <> ''
        AND id_user <> ''
        AND ts_event >= current_date - interval '45 days'
),
encaixes_raw AS (
  SELECT
    evt.event_date,
  	evt.user_id,
    evt.house_id,
    evt.target_date,
    evt.alert_slot_from,
    evt.alert_slot_to,
  	CASE 
      WHEN etb.user_id IS NOT NULL THEN 1 
      ELSE 0 
    END AS encaixe_realizado,
 	  RANK() OVER(PARTITION BY evt.user_id, evt.house_id ORDER BY evt.event_date DESC) AS rank_enc
  FROM 
    visit_hoursalert_confirmed evt
  LEFT JOIN 
    encaixe_to_booking etb
      ON etb.user_id = evt.user_id
        AND etb.house_id = evt.house_id
),
encaixes_temp AS (
  SELECT DISTINCT
    user_id,
    house_id,
    h.id_region AS region_id,
    event_date,
    target_date,
    slot,
    encaixe_realizado,
    1.0/CAST(count(slot) OVER(PARTITION BY enc.user_id,enc.house_id, enc.target_date) AS DECIMAL) AS slot_share_encaixe
  FROM
    encaixes_raw enc
  JOIN 
    slot_series ss 
      ON ss.slot BETWEEN enc.alert_slot_FROM AND enc.alert_slot_to
  JOIN 
    datalake_ebdb_clean_prod.house h 
      ON h.id = enc.house_id
  WHERE
    enc.rank_enc = 1
    AND enc.user_id IS NOT NULL
    AND enc.target_date IS NOT NULL
    AND h.id_region IS NOT NULL
),
blocked_houses AS (
  SELECT
    *
  FROM (
    SELECT
      vs.id_house AS house_id,
      vs.status,
      CAST(from_unixtime(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP) AS init,
      COALESCE(LEAD(CAST(from_unixtime(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP)) OVER(partition by vs.id_house ORDER BY r.ts_revision), current_date) AS "end"
    FROM 
      datalake_ebdb_clean_prod.house_visit_status_aud vs
    JOIN 
      datalake_ebdb_clean_prod.user_revision_entity r
        ON vs.rev = r.id 
          AND mod_status = true
  )
  WHERE
    status = 'BLOCKED'
),
suspended_houses AS (
  --Filter status=suspenso after define 'init' AND 'end'
  SELECT
    *
  FROM (
    SELECT
      h.id_house AS house_id,
      h.status,
      CAST(from_unixtime(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP) AS init,
      COALESCE(LEAD(CAST(from_unixtime(CAST(r.ts_revision/1000 AS BIGINT)) AS TIMESTAMP)) OVER(partition by id_house ORDER BY r.ts_revision), current_date) AS "end"
    FROM 
      datalake_ebdb_clean_prod.house_aud h
    JOIN 
      datalake_ebdb_clean_prod.user_revision_entity r
        ON h.rev = r.id
          AND h.mod_status = true
  )
  WHERE
    status = 'suspenso'
),
 -- !! NEW canceled bookings that are considered repressed demand
cant_find_another_agent AS (
	SELECT DISTINCT
		id_visitor AS user_id,
		id_property AS house_id,
		CAST(slot_dia AS BIGINT) AS slot_dia,
		dt_scheduling,
		DATE(dt_scheduling) AS visit_date,
		status
	FROM 
    public.dim_booking
  WHERE 
    type = 'Visita'
    AND status = 'Cancelado'
    AND cancellation_reason = 'CANCELED_CANT_FIND_ANOTHER_AGENT'
    AND DATE(dt_scheduling) >= current_date - interval '45 days'
),
encaixes_clean AS (
  SELECT
    region_id,
    MAX(t.house_id) house_id,
    t.user_id,
    event_date,
    target_date,
    slot,
    slot_share_encaixe,
    CASE 
      WHEN encaixe_realizado = 0 AND (t.event_date BETWEEN bh.init AND bh."end") AND bh.status = 'BLOCKED' THEN slot_share_encaixe 
    END AS slot_share_nao_realizados_por_bloqueio,
    CASE 
      WHEN encaixe_realizado = 0 AND (t.event_date BETWEEN sh.init AND sh."end") AND sh.status = 'suspenso' THEN slot_share_encaixe 
    END AS slot_share_nao_realizados_por_suspensao,
    CASE 
      WHEN encaixe_realizado = 0 AND (((t.event_date BETWEEN sh.init AND sh."end") AND sh.status = 'suspenso') OR ((t.event_date BETWEEN bh.init AND bh."end") AND bh.status = 'BLOCKED')) THEN slot_share_encaixe
    END AS slot_share_nao_realizados_por_bloqueio_suspensao,
    CASE 
      WHEN encaixe_realizado = 1 THEN slot_share_encaixe 
    END AS slot_share_encaixe_realizado,
    CASE 
      WHEN encaixe_realizado = 0 THEN slot_share_encaixe 
    END AS slot_share_encaixe_nao_realizado,
    CASE 
      WHEN encaixe_realizado = 0
        AND (
            (CAST(slot AS BIGINT) BETWEEN 0 AND 3 AND hs.hours_available_08to09 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 4 AND 7 AND hs.hours_available_09to10 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 8 AND 11 AND hs.hours_available_10to11 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 12 AND 15 AND hs.hours_available_11to12 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 16 AND 19 AND hs.hours_available_12to13 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 20 AND 23 AND hs.hours_available_13to14 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 24 AND 27 AND hs.hours_available_14to15 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 28 AND 31 AND hs.hours_available_15to16 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 32 AND 35 AND hs.hours_available_16to17 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 36 AND 39 AND hs.hours_available_17to18 = false)
            OR (CAST(slot AS BIGINT) BETWEEN 40 AND 43 AND hs.hours_available_18to19 = false)
          ) THEN slot_share_encaixe
    END AS slot_share_nao_realizados_por_agenda, 
    CASE
      WHEN encaixe_realizado = 0 AND (
        ((t.event_date BETWEEN sh.init AND sh."end") AND sh.status = 'suspenso') 
        OR ((t.event_date BETWEEN bh.init AND bh."end") AND bh.status = 'BLOCKED')
        OR (
          (CAST(slot AS BIGINT) BETWEEN 0 AND 3 AND hs.hours_available_08to09 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 4 AND 7 AND hs.hours_available_09to10 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 8 AND 11 AND hs.hours_available_10to11 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 12 AND 15 AND hs.hours_available_11to12 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 16 AND 19 AND hs.hours_available_12to13 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 20 AND 23 AND hs.hours_available_13to14 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 24 AND 27 AND hs.hours_available_14to15 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 28 AND 31 AND hs.hours_available_15to16 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 32 AND 35 AND hs.hours_available_16to17 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 36 AND 39 AND hs.hours_available_17to18 = false)
          OR (CAST(slot AS BIGINT) BETWEEN 40 AND 43 AND hs.hours_available_18to19 = false)
        )
      ) THEN slot_share_encaixe
    END AS slot_share_nao_realizados_por_bloqueio_suspensao_agenda,
    CASE 
      WHEN encaixe_realizado = 1 AND cfaa.status = 'Cancelado' THEN slot_share_encaixe 
    END AS slot_share_encaixe_nao_realizado_cant_find_another_agent,--NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!!
    CAST(hs.hours_available_08to09 AS BIGINT) + CAST(hs.hours_available_09to10 AS BIGINT) + CAST(hs.hours_available_10to11 AS BIGINT) +
    CAST(hs.hours_available_11to12 AS BIGINT) + CAST(hs.hours_available_12to13 AS BIGINT) + CAST(hs.hours_available_13to14 AS BIGINT) +
    CAST(hs.hours_available_14to15 AS BIGINT) + CAST(hs.hours_available_15to16 AS BIGINT) + CAST(hs.hours_available_16to17 AS BIGINT) +
    CAST(hs.hours_available_17to18 AS BIGINT) + CAST(hs.hours_available_18to19 AS BIGINT) AS slots_disponiveis_target_date,
    CASE 
      WHEN encaixe_realizado = 0 AND visit_intent = 'SALE' THEN slot_share_encaixe 
      ELSE NULL 
    END AS slot_share_ocupado_por_visita_sale
  FROM
    encaixes_temp t
  LEFT JOIN 
    house_available_hours hs 
      ON CAST(t.house_id AS BIGINT) = hs.id_house
        AND CAST(hs.day_of_week AS BIGINT) = extract(dow FROM t.target_date)
        AND event_date BETWEEN hs.available_started_date AND COALESCE(hs.available_ended_date, (date_add('day',2,current_date)))
  LEFT JOIN 
    blocked_houses bh 
      ON (t.house_id = CAST(bh.house_id AS VARCHAR)
        AND t.event_date BETWEEN bh.init AND bh."end")
  LEFT JOIN 
    suspended_houses sh 
      ON (t.house_id = CAST(sh.house_id AS VARCHAR)
        AND t.event_date BETWEEN sh.init AND sh."end")
  LEFT JOIN 
    booking_for_sale bfs
      ON CAST(t.house_id AS BIGINT) = CAST(bfs.house_id AS BIGINT)
        AND CAST(t.user_id AS BIGINT) = CAST(bfs.user_id AS BIGINT)
        AND t.target_date = bfs.visit_date
        AND t.slot = bfs.slot_dia
  LEFT JOIN 
    cant_find_another_agent cfaa
      ON CAST(t.house_id AS BIGINT) = CAST(cfaa.house_id AS BIGINT)
        AND t.target_date = cfaa.visit_date
        AND t.slot = cfaa.slot_dia
  GROUP BY 1,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17
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
    SUM(
      CASE 
        WHEN slots_disponiveis_target_date = 0 THEN slot_share_encaixe 
        END
    ) AS encaixes_em_imovel_sem_slot_disponivel_target_date,
    SUM(slot_share_ocupado_por_visita_sale) AS share_encaixes_nao_realizados_por_visita_sale,
    SUM(COALESCE(slot_share_encaixe_nao_realizado,0) + COALESCE(slot_share_encaixe_nao_realizado_cant_find_another_agent,0) - (COALESCE(slot_share_nao_realizados_por_bloqueio_suspensao_agenda,0) + COALESCE(slot_share_ocupado_por_visita_sale,0))) AS share_encaixes_nao_realizados_por_agent
  FROM
      encaixes_clean
  GROUP BY 1,2,3,4,5,6
)
SELECT
  d.region_code,
  d.city_name,
  d.city_group,
  event_date,
  target_date AS visit_date,
  d.week_start,
  CAST(d.date AS TIMESTAMP) + interval '8 hours' + (interval '15 minutes') * d.slot AS visit_hour,
  d.hour,
  d.faixa,
  enc.user_id,
  enc.house_id,
  enc.slot,
  enc.share_encaixes_total AS sum_encaixes_total,
  enc.share_encaixes_realizados AS sum_share_encaixes_realizados,
  enc.share_encaixes_nao_realizados AS sum_encaixes_nao_realizados,
  enc.share_encaixes_nao_realizados_cant_find_another_agent AS sum_encaixes_nao_realizados_cant_find_another_agent,
  enc.share_encaixes_nao_realizados_por_agenda AS sum_encaixes_nao_realizados_por_agenda,
  enc.share_encaixes_nao_realizados_por_bloqueio AS sum_encaixes_nao_realizados_por_bloqueio,
  enc.share_encaixes_nao_realizados_por_suspensao AS sum_encaixes_nao_realizados_por_suspensao,
  enc.share_encaixes_nao_realizados_por_bloqueio_suspensao AS sum_encaixes_nao_realizados_por_bloqueio_suspensao,
  enc.share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda AS sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
  enc.encaixes_em_imovel_sem_slot_disponivel_target_date AS sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
  enc.share_encaixes_nao_realizados_por_visita_sale AS sum_encaixes_nao_realizados_por_visita_sale,
  enc.share_encaixes_nao_realizados_por_agent AS sum_encaixes_nao_realizados_por_agent
FROM
  encaixes_agg enc
LEFT JOIN 
  dimensions d 
    ON enc.region_id = d.region_id
      AND enc.target_date = d.date
      AND enc.slot = d.slot