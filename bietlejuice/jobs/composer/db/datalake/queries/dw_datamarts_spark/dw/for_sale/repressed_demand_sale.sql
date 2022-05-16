WITH house_available_hours AS (
    WITH imovel_aud AS (
        SELECT
            CAST(FROM_UNIXTIME(CAST(ts_revision AS BIGINT)/1000) AS TIMESTAMP) AS date_time,
            hou.*
        FROM 
            datalake_ebdb_clean.house_weekly_schedule_aud AS hou
        JOIN
            datalake_ebdb_clean.user_revision_entity AS ure
                ON hou.rev = ure.id
        JOIN
            datalake_ebdb_clean.listing_business_context AS lbc 
                ON hou.id_house = lbc.id_house
                AND business_context = 'SALE'
    ),
    house_available AS (
        SELECT
            ia.id_house,
            ia.date_time AS available_started_date,
            LEAD(date_time) OVER(
                PARTITION BY
                    id_house,
                    ia.weekday
                ORDER BY
                    rev
            ) AS available_ended_date,
            ia.weekday AS day_of_week,
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
        CAST(day_of_week AS BIGINT) AS day_of_week,
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
        house_available AS ha
),
date_series AS (
    SELECT
        date AS DATE,
        week_day,
        weekday_name,
        week_start,
        CASE 
            WHEN week_day = 6 THEN 'Saturday' 
            WHEN week_day = 0 THEN 'Sunday' 
            ELSE 'Weekday' 
        END AS week_day_type
    FROM
        dw_public.dim_date AS dd
    WHERE
        date >= '2020-01-13'
        AND week_start <= CURRENT_DATE
        AND date IS NOT NULL
),
regions AS (
    SELECT DISTINCT
        fv.sk_region AS region_id,
        dr.region_code,
        dr.city_group,
        dr.city_name
    FROM
        dw_sale.fact_visits AS fv
    LEFT JOIN
        dw_public.dim_region AS dr
            ON dr.id = fv.sk_region
    WHERE
        dr.sk_region IS NOT NULL
),
slot_series AS (
    SELECT
        EXPLODE(SEQUENCE(0, 99)) AS slot
),
dimensions AS (
    SELECT
        CAST(r.region_id AS BIGINT) AS region_id,
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
        WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 4 AND 19 THEN  '2) Weekday 9-13h'
        WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 20 AND 31 THEN  '3) Weekday 13-16h'
        WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 32 AND 35 THEN  '4) Weekday 16-17h'
        WHEN ds.week_day BETWEEN 1 AND 5 AND ss.slot BETWEEN 36 AND 43 THEN '5) Extended hours'
        WHEN ds.week_day = 6 THEN '6) Saturday all hours'
        WHEN ds.week_day = 0 THEN '7) Sunday all hours'
    END AS faixa              
    FROM
        regions AS r
    CROSS JOIN
        date_series AS ds
    CROSS JOIN
        slot_series AS ss
    WHERE
        date >= '2020-01-13'
),
encaixe_to_booking AS (
    SELECT DISTINCT
        id_visitor AS user_id,
        id_property AS house_id
    FROM
        dw_public.dim_booking
    WHERE
        type = 'Visita'
        AND visit_intent = 'SALE'
        AND dt_scheduling >= '2020-01-13'
),
booking_for_rent AS (
    SELECT DISTINCT
        id_visitor AS user_id,
        id_property AS house_id,
        slot_dia,
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
        AND dt_scheduling >= '2020-01-13'
        AND (
            status = 'Realizado' 
            OR status = 'Marcado'
            OR (status = 'Cancelado' AND DATE(dt_scheduling) = DATE(dt_cancel))
        )
),
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
        (year > 2020
        OR (year = 2020 AND month > 1)
        OR  (year = 2020 AND month = 1 AND day >= 13))
        AND id_user <> ''
        AND TRIM(ep_business_context) = 'sale'
        AND ep_house_id IS NOT NULL
),
encaixes_raw AS (
    SELECT
        evt.event_date,
        evt.user_id,
        evt.house_id,
        evt.target_date,
        evt.alert_slot_from,
        evt.alert_slot_to,
        CASE WHEN etb.user_id IS NOT NULL THEN 1 else 0 END AS encaixe_realizado,
        RANK() OVER (PARTITION BY evt.user_id, evt.house_id ORDER BY evt.event_date DESC) AS rank_enc
    FROM 
        visit_hoursalert_confirmed AS evt
    LEFT JOIN 
        encaixe_to_booking AS etb 
            ON etb.user_id = evt.user_id
            AND etb.house_id = evt.house_id
),
encaixes_temp AS (
    SELECT /*+ RANGE_JOIN(ss, 43) */ DISTINCT
        enc.encaixe_realizado,
        enc.user_id,
        enc.house_id,
        h.id_region AS region_id,
        enc.target_date,
        enc.event_date,
        ss.slot,
        1.0 / CAST(COUNT(slot) OVER (PARTITION BY enc.user_id, enc.house_id, enc.target_date) AS DECIMAL) AS slot_share_encaixe
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
        AND enc.target_date IS NOT NULL
        AND h.id_region IS NOT NULL
),
aux_blocked_houses AS (
    SELECT
        vs.id_house AS house_id,
        vs.status,
        CAST(FROM_UNIXTIME(CAST(r.ts_revision / 1000 AS BIGINT)) AS TIMESTAMP) AS init,
        COALESCE(
            LEAD(CAST(FROM_UNIXTIME(CAST(r.ts_revision / 1000 AS BIGINT)) AS TIMESTAMP)) OVER (
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
            ON vs.REV = r.id
            AND mod_status = true
    JOIN
        datalake_ebdb_clean.listing_business_context AS lbc
            ON lbc.id_house = vs.id_house
    WHERE
        lbc.status <> 'EDITING'
        AND lbc.business_context = 'SALE'
),
blocked_houses AS (
    SELECT *
    FROM
        aux_blocked_houses
    WHERE
        status = 'BLOCKED'
),
aux_suspended_houses AS (
    SELECT
        laud.id_house AS house_id,
        laud.status,
        CAST(FROM_UNIXTIME(CAST(r.ts_revision / 1000 AS BIGINT)) AS TIMESTAMP) AS init,
        COALESCE(
            LEAD(CAST(FROM_UNIXTIME(CAST(r.ts_revision / 1000 AS BIGINT)) AS TIMESTAMP)) OVER (
                PARTITION BY
                    laud.id_house
                ORDER BY
                    r.ts_revision
            ),
            CURRENT_DATE
        ) AS `end`
        FROM
            datalake_ebdb_clean.listing_business_context_aud AS laud
        JOIN
            datalake_ebdb_clean.user_revision_entity AS r 
                ON laud.rev = r.id 
                AND laud.mod_status = '1'
    WHERE
        laud.business_context = 'SALE'
),
suspended_houses AS (
    SELECT *
    FROM
        aux_suspended_houses
    WHERE
        status = 'SUSPENDED'
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
        dw_public.dim_booking
    WHERE
        type = 'Visita'
        AND visit_intent = 'SALE'
        AND status = 'Cancelado'
        AND cancellation_reason = 'CANCELED_CANT_FIND_ANOTHER_AGENT'
        AND dt_scheduling >= CURRENT_DATE - INTERVAL 45 DAYS
),
encaixes_clean AS (
    SELECT
        region_id,
        target_date,
        slot,
        slot_share_encaixe, 
        CASE
            WHEN encaixe_realizado = 0 
            AND (t.event_date BETWEEN bh.init AND bh.`end`) 
            AND bh.status = 'BLOCKED'
                THEN slot_share_encaixe 
        END AS slot_share_nao_realizados_por_bloqueio,
          CASE
            WHEN encaixe_realizado = 0
            AND (t.event_date BETWEEN sh.init AND sh.`end`)
            AND sh.status = 'SUSPENDED'
                THEN slot_share_encaixe
        END AS slot_share_nao_realizados_por_suspensao,
          CASE
            WHEN encaixe_realizado = 0
            AND (((t.event_date BETWEEN sh.init AND sh.`end`) AND sh.status = 'SUSPENDED')
            OR ((t.event_date BETWEEN bh.init AND bh.`end`) AND bh.status = 'BLOCKED')) 
                THEN slot_share_encaixe
        END AS slot_share_nao_realizados_por_bloqueio_suspensao,
          CASE
            WHEN encaixe_realizado = 1 THEN slot_share_encaixe
        END AS slot_share_encaixe_realizado,
          CASE
            WHEN encaixe_realizado = 0 THEN slot_share_encaixe END AS slot_share_encaixe_nao_realizado,
          CASE
            WHEN encaixe_realizado = 0
            AND ((slot BETWEEN  0 AND  3 AND hs.hours_available_08to09 = false)
                OR (slot BETWEEN  4 AND  7 AND hs.hours_available_09to10 = false)
                OR (slot BETWEEN  8 AND 11 AND hs.hours_available_10to11 = false)
                OR (slot BETWEEN 12 AND 15 AND hs.hours_available_11to12 = false)
                OR (slot BETWEEN 16 AND 19 AND hs.hours_available_12to13 = false)
                OR (slot BETWEEN 20 AND 23 AND hs.hours_available_13to14 = false)
                OR (slot BETWEEN 24 AND 27 AND hs.hours_available_14to15 = false)
                OR (slot BETWEEN 28 AND 31 AND hs.hours_available_15to16 = false)
                OR (slot BETWEEN 32 AND 35 AND hs.hours_available_16to17 = false)
                OR (slot BETWEEN 36 AND 39 AND hs.hours_available_17to18 = false)
                OR (slot BETWEEN 40 AND 43 AND hs.hours_available_18to19 = false)
            )
                THEN slot_share_encaixe
        END AS slot_share_nao_realizados_por_agenda,
          CASE
            WHEN encaixe_realizado = 0
            AND (
                ((t.event_date BETWEEN sh.init AND sh.`end`) AND sh.status = 'suspenso')
                OR (
                    (t.event_date BETWEEN bh.init AND bh.`end`) AND bh.status = 'BLOCKED')
                    OR ((slot BETWEEN  0 AND  3 AND hs.hours_available_08to09 = false)
                    OR (slot BETWEEN  4 AND  7 AND hs.hours_available_09to10 = false)
                    OR (slot BETWEEN  8 AND 11 AND hs.hours_available_10to11 = false)
                    OR (slot BETWEEN 12 AND 15 AND hs.hours_available_11to12 = false)
                    OR (slot BETWEEN 16 AND 19 AND hs.hours_available_12to13 = false)
                    OR (slot BETWEEN 20 AND 23 AND hs.hours_available_13to14 = false)
                    OR (slot BETWEEN 24 AND 27 AND hs.hours_available_14to15 = false)
                    OR (slot BETWEEN 28 AND 31 AND hs.hours_available_15to16 = false)
                    OR (slot BETWEEN 32 AND 35 AND hs.hours_available_16to17 = false)
                    OR (slot BETWEEN 36 AND 39 AND hs.hours_available_17to18 = false)
                    OR (slot BETWEEN 40 AND 43 AND hs.hours_available_18to19 = false)
                )
            )
            THEN slot_share_encaixe
        END AS slot_share_nao_realizados_por_bloqueio_suspensao_agenda,
        CASE
            WHEN encaixe_realizado = 1
            AND cfaa.status = 'Cancelado'
                THEN slot_share_encaixe
        END AS slot_share_nao_realizado_cant_find_another_agent,--NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!! NOVIDADE!!
        CAST(hs.hours_available_08to09 AS BIGINT) + CAST(hs.hours_available_09to10 AS BIGINT) + CAST(hs.hours_available_10to11 AS BIGINT) +
        CAST(hs.hours_available_11to12 AS BIGINT) + CAST(hs.hours_available_12to13 AS BIGINT) + CAST(hs.hours_available_13to14 AS BIGINT) +
        CAST(hs.hours_available_14to15 AS BIGINT) + CAST(hs.hours_available_15to16 AS BIGINT) + CAST(hs.hours_available_16to17 AS BIGINT) +
        CAST(hs.hours_available_17to18 AS BIGINT) + CAST(hs.hours_available_18to19 AS BIGINT) AS slots_disponiveis_target_date,
        CASE
            WHEN encaixe_realizado = 0
            AND visit_intent = 'RENT'
                THEN slot_share_encaixe
            ELSE NULL 
        END AS slot_share_ocupado_por_visita_rent
    FROM
        encaixes_temp AS t
    LEFT JOIN
        house_available_hours AS hs
            ON t.house_id = hs.id_house
            AND hs.day_of_week = EXTRACT(dow FROM t.target_date) - 1
            AND t.event_date BETWEEN hs.available_started_date AND COALESCE(hs.available_ended_date, (DATE_ADD(CURRENT_DATE, 2)))
    LEFT JOIN blocked_houses AS bh
        ON t.house_id = bh.house_id
        AND t.event_date BETWEEN bh.init AND bh.`end`
    LEFT JOIN suspended_houses AS sh
        ON t.house_id = sh.house_id
        AND t.event_date BETWEEN sh.init AND sh.`end`
    LEFT JOIN booking_for_rent AS bfr
        ON t.house_id = bfr.house_id
        AND t.target_date = bfr.visit_date
        AND t.slot = bfr.slot_dia
    LEFT JOIN cant_find_another_agent AS cfaa
        ON CAST(t.house_id AS BIGINT) = CAST(cfaa.house_id AS BIGINT)
        AND t.target_date = cfaa.visit_date
        AND t.slot = cfaa.slot_dia
    WHERE
        target_date >= '2020-01-13'
),
encaixes_agg AS (
    SELECT
        ec.region_id,
        ec.target_date,
        ec.slot,
        SUM(ec.slot_share_encaixe) AS share_encaixes_total,
        SUM(COALESCE(slot_share_encaixe_realizado,0) - COALESCE(slot_share_nao_realizado_cant_find_another_agent,0)) AS share_encaixes_realizados, -- removing referring slots FROM bookings cancelled WITH CANT FIND ANOTHER AGENT reason
        SUM(COALESCE(slot_share_encaixe_nao_realizado,0) + COALESCE(slot_share_nao_realizado_cant_find_another_agent,0)) AS share_encaixes_nao_realizados,
        SUM(ec.slot_share_nao_realizados_por_agenda) AS share_encaixes_nao_realizados_por_agenda,
        SUM(ec.slot_share_nao_realizados_por_bloqueio) AS share_encaixes_nao_realizados_por_bloqueio,
        SUM(ec.slot_share_nao_realizados_por_suspensao) AS share_encaixes_nao_realizados_por_suspensao,
        SUM(ec.slot_share_nao_realizados_por_bloqueio_suspensao) AS share_encaixes_nao_realizados_por_bloqueio_suspensao,
        SUM(ec.slot_share_nao_realizados_por_bloqueio_suspensao_agenda) AS share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
        SUM(CASE WHEN ec.slots_disponiveis_target_date = 0 THEN ec.slot_share_encaixe end) AS encaixes_em_imovel_sem_slot_disponivel_target_date,
        SUM(ec.slot_share_ocupado_por_visita_rent) AS share_encaixes_nao_realizados_por_visita_rent,
        SUM(slot_share_nao_realizado_cant_find_another_agent) AS share_nao_realizado_cant_find_another_agent,
        SUM(COALESCE(slot_share_encaixe_nao_realizado,0) + COALESCE(slot_share_nao_realizado_cant_find_another_agent,0) - (COALESCE(ec.slot_share_nao_realizados_por_bloqueio_suspensao_agenda,0) + COALESCE(ec.slot_share_ocupado_por_visita_rent,0))) AS share_encaixes_nao_realizados_por_agent
    FROM
        encaixes_clean AS ec
    GROUP BY 1, 2, 3
),
bookings_raw AS (
    SELECT
        bk.id_visitor AS user_id,
           bk.id_property AS house_id,
           DATE(bk.dt_scheduling) AS visit_date,
           bk.slot_dia AS slot,
           h.id_region AS region_id,
           RANK() OVER (PARTITION BY bk.id_visitor, bk.id_property ORDER BY bk.dt_created DESC) AS rank_bkg
    FROM
        dw_public.dim_booking AS bk
    JOIN
        datalake_ebdb_clean.house AS h
            ON h.id = bk.id_property
    WHERE
        bk.type = 'Visita'
        AND bk.visit_intent = 'SALE'
        AND (cancellation_reason IS NULL OR cancellation_reason != 'CANCELED_CANT_FIND_ANOTHER_AGENT') -- removing all bookings that were cancelled WITH thIS reason, so we can count them AS still repressed demand
        AND dt_scheduling >= '2020-01-13'
),
bookings_clean AS (
    SELECT
        region_id,
        visit_date,
        slot,
        COUNT(DISTINCT user_id || house_id) AS unique_bookings
    FROM
        bookings_raw
    WHERE
        rank_bkg = 1
        AND user_id IS NOT NULL
        AND region_id IS NOT NULL
    GROUP BY
        1, 2, 3
)
SELECT
    d.region_code,
    d.city_group AS city_group,
    d.city_name,
    CAST(d.week_start AS STRING) AS week_start,
    CAST(d.date AS TIMESTAMP) AS date,
    d.slot,
    d.hour,
    d.faixa,
    SUM(unique_bookings) AS sum_bookings,
    SUM(enc.share_encaixes_total) AS sum_encaixes,
    SUM(enc.share_encaixes_realizados) AS sum_encaixes_realized,
    SUM(enc.share_encaixes_nao_realizados) AS sum_encaixes_not_realized,
    SUM(enc.share_nao_realizado_cant_find_another_agent) AS sum_encaixes_nao_realizado_cant_find_another_agent,
    SUM(enc.share_encaixes_nao_realizados_por_agenda) AS sum_encaixes_nao_realizados_por_agenda,
    SUM(enc.share_encaixes_nao_realizados_por_bloqueio) AS sum_encaixes_nao_realizados_por_bloqueio,
    SUM(enc.share_encaixes_nao_realizados_por_suspensao) AS sum_encaixes_nao_realizados_por_suspensao,
    SUM(enc.share_encaixes_nao_realizados_por_bloqueio_suspensao) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao,
    SUM(enc.share_encaixes_nao_realizados_por_bloqueio_suspensao_agenda) AS sum_encaixes_nao_realizados_por_bloqueio_suspensao_agenda,
    SUM(enc.encaixes_em_imovel_sem_slot_disponivel_target_date) AS sum_encaixes_em_imovel_sem_slot_disponivel_target_date,
    SUM(enc.share_encaixes_nao_realizados_por_visita_rent) AS sum_encaixes_nao_realizados_por_visita_rent,
    SUM(enc.share_encaixes_nao_realizados_por_agent) AS sum_encaixes_nao_realizados_por_agent
FROM
    dimensions AS d
LEFT JOIN
    bookings_clean AS bk
        ON bk.region_id = d.region_id
        AND bk.visit_date = d.date
        AND bk.slot = d.slot
LEFT JOIN
    encaixes_agg AS enc
        ON enc.region_id = d.region_id
        AND enc.target_date = d.date
        AND enc.slot = d.slot
WHERE
    faixa IS NOT NULL
    AND COALESCE(bk.slot, enc.slot) IS NOT NULL
GROUP BY
    1, 2, 3, 4, 5, 6, 7, 8