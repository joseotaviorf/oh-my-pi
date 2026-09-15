-- Sale BP cohort funnel for Find health metrics.
-- One table covers both the 4-week and 8-week mature windows: window length is
-- a CTE parameter (window_defs), not a copied query. Channel labels (Agent /
-- TQC 1P / TQC 3P / SelfService / Concierge / Secretaria) are applied once
-- after the cohort union and reused on the event-anchored visit side.
-- As-of date is the DAG load end date so backfills stay deterministic.
-- Each run writes one dt_snapshot partition (year/month/day of {end_date})
-- so monthly columns and Latest Mature Cohort can be rebuilt for any past
-- report date. Source scan is exactly {days_past_120} calendar days before
-- as-of (the DAG load end date). MONTHLY drops any month that starts before
-- that lookback so the first column is never a partial month. Older IBM
-- months live on earlier dt_snapshot partitions (use those for YoY).
-- Sources are the enrich tables behind the original Trino DW query
-- (prospect_daily_results, booking, sale_offer, sale_demand_events) plus
-- concierge_indirect_vb: SelfService listing-page bookings after a Concierge
-- carousel are remapped to Concierge on origin-anchored BPs and event-anchored
-- visits. Direct WhatsApp/native Concierge is already Concierge in
-- prospect_daily_results. Agent / Rede / Secretaria are not remapped.
-- Concierge vs SelfService therefore diverge from the original IBM Trino query;
-- Consolidado does not.
WITH as_of AS (
    SELECT
        DATE('{end_date}') AS dt_as_of
),
window_defs AS (
    SELECT
        4 AS cohort_window_weeks,
        28 AS window_days
    UNION ALL
    SELECT
        8 AS cohort_window_weeks,
        56 AS window_days
),
window_dates AS (
    SELECT
        wd.cohort_window_weeks,
        wd.window_days - 1 AS window_offset_days,
        ao.dt_as_of,
        DATE_SUB(ao.dt_as_of, {days_past_120}) AS dt_history_start,
        DATE_SUB(ao.dt_as_of, wd.window_days) AS dt_last_mature_bp
    FROM
        window_defs AS wd
    CROSS JOIN
        as_of AS ao
),
params AS (
    SELECT
        wdt.cohort_window_weeks,
        wdt.window_offset_days,
        wdt.dt_as_of,
        wdt.dt_history_start,
        wdt.dt_last_mature_bp,
        DATE_SUB(wdt.dt_last_mature_bp, 30) AS dt_latest_mature_start,
        DATE_SUB(
            CAST(
                DATE_TRUNC(
                    'month',
                    CAST(DATE_ADD(wdt.dt_last_mature_bp, 1) AS TIMESTAMP)
                ) AS DATE
            ),
            1
        ) AS dt_last_full_mature_month_end
    FROM
        window_dates AS wdt
),
scan_bounds AS (
    SELECT
        MIN(p.dt_history_start) AS dt_history_start,
        MAX(p.dt_last_mature_bp) AS dt_last_mature_bp,
        MAX(p.window_offset_days) AS max_window_offset_days,
        MAX(p.dt_as_of) AS dt_as_of
    FROM
        params AS p
),
indirect_concierge_visits AS (
    SELECT DISTINCT
        civ.id_visit
    FROM
        datalake_search.concierge_indirect_vb AS civ
    CROSS JOIN
        scan_bounds AS sb
    WHERE
        LOWER(civ.business_context) = 'sale'
        AND civ.is_indirect_visit_booked = TRUE
        AND civ.year >= YEAR(sb.dt_history_start)
        AND civ.year <= YEAR(sb.dt_as_of)
),
bp_events AS (
    SELECT
        CAST(bk.id_visitor AS STRING) AS id_user,
        pdr.id_booking,
        pdr.ts_event AS ts_bp,
        CAST(
            FROM_UTC_TIMESTAMP(pdr.ts_event, 'America/Sao_Paulo') AS DATE
        ) AS dt_bp,
        CASE
            WHEN icv.id_visit IS NOT NULL
                AND pdr.operation_channel = 'SelfService'
                THEN 'Concierge'
            ELSE pdr.operation_channel
        END AS operation_channel,
        pdr.referral_type
    FROM
        datalake_demand_flows.prospect_daily_results AS pdr
    INNER JOIN
        datalake_booking.booking AS bk
            ON pdr.id_booking = bk.id
    LEFT JOIN
        indirect_concierge_visits AS icv
            ON icv.id_visit = COALESCE(pdr.id_visit, bk.id_visit)
    CROSS JOIN
        scan_bounds AS sb
    WHERE
        LOWER(pdr.business_context) = 'sale'
        AND pdr.event_type = 'CONVERSION'
        AND pdr.event_name IN (
            'USER FIRST ACTIVATION',
            'USER FIRST ACTIVATION IN CITY GROUP',
            'USER RECOVERY',
            'USER RECOVERY IN OTHER CITY GROUP'
        )
        AND pdr.year >= YEAR(sb.dt_history_start)
        AND pdr.year <= YEAR(sb.dt_as_of)
        AND CAST(
            FROM_UTC_TIMESTAMP(pdr.ts_event, 'America/Sao_Paulo') AS DATE
        ) BETWEEN sb.dt_history_start AND sb.dt_last_mature_bp
),
monthly_bp_ranked AS (
    SELECT
        e.id_user,
        e.id_booking,
        e.ts_bp,
        e.dt_bp,
        e.operation_channel,
        e.referral_type,
        p.cohort_window_weeks,
        p.window_offset_days,
        CAST(DATE_TRUNC('month', CAST(e.dt_bp AS TIMESTAMP)) AS DATE) AS dt_cohort_start,
        ROW_NUMBER() OVER (
            PARTITION BY
                p.cohort_window_weeks,
                e.id_user,
                CAST(DATE_TRUNC('month', CAST(e.dt_bp AS TIMESTAMP)) AS DATE)
            ORDER BY
                e.ts_bp,
                e.id_booking
        ) AS rn
    FROM
        bp_events AS e
    CROSS JOIN
        params AS p
    WHERE
        e.dt_bp <= p.dt_last_full_mature_month_end
        AND CAST(DATE_TRUNC('month', CAST(e.dt_bp AS TIMESTAMP)) AS DATE)
            >= p.dt_history_start
),
monthly_cohorts AS (
    SELECT
        mbr.cohort_window_weeks,
        mbr.window_offset_days,
        'MONTHLY' AS cohort_type,
        mbr.dt_cohort_start,
        DATE_SUB(ADD_MONTHS(mbr.dt_cohort_start, 1), 1) AS dt_cohort_end,
        DATE_FORMAT(CAST(mbr.dt_cohort_start AS TIMESTAMP), 'MMM-yy') AS cohort_label,
        mbr.id_user,
        mbr.dt_bp,
        mbr.referral_type,
        mbr.operation_channel
    FROM
        monthly_bp_ranked AS mbr
    WHERE
        mbr.rn = 1
),
latest_bp_ranked AS (
    SELECT
        e.id_user,
        e.id_booking,
        e.ts_bp,
        e.dt_bp,
        e.operation_channel,
        e.referral_type,
        p.cohort_window_weeks,
        p.window_offset_days,
        p.dt_latest_mature_start,
        p.dt_last_mature_bp,
        ROW_NUMBER() OVER (
            PARTITION BY
                p.cohort_window_weeks,
                e.id_user
            ORDER BY
                e.ts_bp,
                e.id_booking
        ) AS rn
    FROM
        bp_events AS e
    CROSS JOIN
        params AS p
    WHERE
        e.dt_bp BETWEEN p.dt_latest_mature_start AND p.dt_last_mature_bp
),
latest_cohort AS (
    SELECT
        lbr.cohort_window_weeks,
        lbr.window_offset_days,
        'LATEST_MATURE' AS cohort_type,
        lbr.dt_latest_mature_start AS dt_cohort_start,
        lbr.dt_last_mature_bp AS dt_cohort_end,
        'Latest Mature Cohort' AS cohort_label,
        lbr.id_user,
        lbr.dt_bp,
        lbr.referral_type,
        lbr.operation_channel
    FROM
        latest_bp_ranked AS lbr
    WHERE
        lbr.rn = 1
),
cohorts_raw AS (
    SELECT
        mc.cohort_window_weeks,
        mc.window_offset_days,
        mc.cohort_type,
        mc.dt_cohort_start,
        mc.dt_cohort_end,
        mc.cohort_label,
        mc.id_user,
        mc.dt_bp,
        mc.referral_type,
        mc.operation_channel
    FROM
        monthly_cohorts AS mc
    UNION ALL
    SELECT
        lc.cohort_window_weeks,
        lc.window_offset_days,
        lc.cohort_type,
        lc.dt_cohort_start,
        lc.dt_cohort_end,
        lc.cohort_label,
        lc.id_user,
        lc.dt_bp,
        lc.referral_type,
        lc.operation_channel
    FROM
        latest_cohort AS lc
),
-- Agent/Rede are split by referral_type so origin-anchored and event-anchored
-- sides share the same channel vocabulary.
cohorts AS (
    SELECT
        cr.cohort_window_weeks,
        cr.window_offset_days,
        cr.cohort_type,
        cr.dt_cohort_start,
        cr.dt_cohort_end,
        cr.cohort_label,
        cr.id_user,
        cr.dt_bp,
        CASE
            WHEN cr.operation_channel IN ('Agent', 'Rede') THEN
                CASE
                    WHEN cr.referral_type = 'Agent' THEN 'Agent'
                    WHEN cr.referral_type = 'TQC 1P' THEN 'TQC 1P'
                    WHEN cr.referral_type = 'TQC 3P' THEN 'TQC 3P'
                    ELSE 'Others/Lost Tracking'
                END
            WHEN cr.operation_channel IN ('SelfService', 'Concierge', 'Secretaria')
                THEN cr.operation_channel
            ELSE 'Others/Lost Tracking'
        END AS operation_channel
    FROM
        cohorts_raw AS cr
),
vb_rows AS (
    SELECT DISTINCT
        c.cohort_window_weeks,
        c.cohort_type,
        c.dt_cohort_start,
        c.dt_cohort_end,
        c.cohort_label,
        c.id_user,
        pdr.id_booking
    FROM
        cohorts AS c
    CROSS JOIN
        scan_bounds AS sb
    INNER JOIN
        datalake_booking.booking AS bk
            ON CAST(bk.id_visitor AS STRING) = c.id_user
    INNER JOIN
        datalake_demand_flows.prospect_daily_results AS pdr
            ON pdr.id_booking = bk.id
            AND LOWER(pdr.business_context) = 'sale'
            AND pdr.event_type = 'FLOW'
            AND pdr.event_name = 'VISIT BOOKED'
            AND pdr.year >= YEAR(sb.dt_history_start)
            AND pdr.year <= YEAR(sb.dt_as_of)
            AND CAST(
                FROM_UTC_TIMESTAMP(pdr.ts_event, 'America/Sao_Paulo') AS DATE
            ) BETWEEN c.dt_bp AND DATE_ADD(c.dt_bp, c.window_offset_days)
),
vb_windowed AS (
    SELECT
        vr.cohort_window_weeks,
        vr.cohort_type,
        vr.dt_cohort_start,
        vr.dt_cohort_end,
        vr.cohort_label,
        vr.id_user,
        COUNT(*) AS vb_in_window
    FROM
        vb_rows AS vr
    GROUP BY
        vr.cohort_window_weeks,
        vr.cohort_type,
        vr.dt_cohort_start,
        vr.dt_cohort_end,
        vr.cohort_label,
        vr.id_user
),
vc_os_windowed AS (
    SELECT
        c.cohort_window_weeks,
        c.cohort_type,
        c.dt_cohort_start,
        c.dt_cohort_end,
        c.cohort_label,
        c.id_user,
        COUNT(
            DISTINCT CASE
                WHEN sde.event_name = 'VISIT_COMPLETED' THEN sde.id_booking
            END
        ) AS vc_in_window,
        MAX(
            CASE
                WHEN sde.event_name = 'OFFER_SUBMITTED' THEN 1
                ELSE 0
            END
        ) AS is_os_in_window,
        COUNT(
            CASE
                WHEN sde.event_name = 'OFFER_SUBMITTED' THEN 1
            END
        ) AS os_in_window
    FROM
        cohorts AS c
    CROSS JOIN
        scan_bounds AS sb
    INNER JOIN
        datalake_sale_demand_events.sale_demand_events AS sde
            ON CAST(sde.id_buyer AS STRING) = c.id_user
            AND CAST(
                FROM_UTC_TIMESTAMP(sde.ts_event, 'America/Sao_Paulo') AS DATE
            ) BETWEEN c.dt_bp AND DATE_ADD(
                c.dt_bp,
                c.window_offset_days
            )
            AND CAST(
                FROM_UTC_TIMESTAMP(sde.ts_event, 'America/Sao_Paulo') AS DATE
            ) BETWEEN sb.dt_history_start AND sb.dt_as_of
            AND sde.event_name IN ('VISIT_COMPLETED', 'OFFER_SUBMITTED')
    GROUP BY
        c.cohort_window_weeks,
        c.cohort_type,
        c.dt_cohort_start,
        c.dt_cohort_end,
        c.cohort_label,
        c.id_user
),
ccv_windowed AS (
    SELECT
        c.cohort_window_weeks,
        c.cohort_type,
        c.dt_cohort_start,
        c.dt_cohort_end,
        c.cohort_label,
        c.id_user,
        COUNT(DISTINCT so.id_offer) AS ccv_in_window,
        MAX(1) AS is_ccv_in_window
    FROM
        cohorts AS c
    CROSS JOIN
        scan_bounds AS sb
    INNER JOIN
        datalake_booking.booking AS bk
            ON CAST(bk.id_visitor AS STRING) = c.id_user
    INNER JOIN
        datalake_sale_offer.sale_offer AS so
            ON so.id_booking = bk.id
            AND so.ts_sale_agreement_signed IS NOT NULL
            AND CAST(
                FROM_UTC_TIMESTAMP(
                    so.ts_sale_agreement_signed,
                    'America/Sao_Paulo'
                ) AS DATE
            ) BETWEEN c.dt_bp AND DATE_ADD(c.dt_bp, c.window_offset_days)
            AND CAST(
                FROM_UTC_TIMESTAMP(
                    so.ts_sale_agreement_signed,
                    'America/Sao_Paulo'
                ) AS DATE
            ) BETWEEN sb.dt_history_start AND sb.dt_as_of
    GROUP BY
        c.cohort_window_weeks,
        c.cohort_type,
        c.dt_cohort_start,
        c.dt_cohort_end,
        c.cohort_label,
        c.id_user
),
vb_events_raw AS (
    SELECT
        pdr.id_visit,
        pdr.id_booking,
        pdr.ts_event,
        CASE
            WHEN icv.id_visit IS NOT NULL
                AND pdr.operation_channel = 'SelfService'
                THEN 'Concierge'
            ELSE pdr.operation_channel
        END AS operation_channel,
        pdr.referral_type,
        ROW_NUMBER() OVER (
            PARTITION BY
                pdr.id_visit
            ORDER BY
                pdr.ts_event,
                pdr.id_booking
        ) AS rn_visit
    FROM
        datalake_demand_flows.prospect_daily_results AS pdr
    LEFT JOIN
        indirect_concierge_visits AS icv
            ON icv.id_visit = pdr.id_visit
    CROSS JOIN
        scan_bounds AS sb
    WHERE
        LOWER(pdr.business_context) = 'sale'
        AND pdr.event_type = 'FLOW'
        AND pdr.event_name = 'VISIT BOOKED'
        AND pdr.id_visit IS NOT NULL
        AND pdr.year >= YEAR(sb.dt_history_start)
        AND pdr.year <= YEAR(sb.dt_as_of)
        AND CAST(
            FROM_UTC_TIMESTAMP(pdr.ts_event, 'America/Sao_Paulo') AS DATE
        ) BETWEEN sb.dt_history_start AND sb.dt_as_of
),
vb_visit AS (
    SELECT
        ver.id_visit,
        ver.id_booking AS first_id_booking,
        ver.ts_event AS first_vb_ts,
        CASE
            WHEN ver.operation_channel IN ('Agent', 'Rede') THEN
                CASE
                    WHEN ver.referral_type = 'Agent' THEN 'Agent'
                    WHEN ver.referral_type = 'TQC 1P' THEN 'TQC 1P'
                    WHEN ver.referral_type = 'TQC 3P' THEN 'TQC 3P'
                    ELSE 'Others/Lost Tracking'
                END
            WHEN ver.operation_channel IN ('SelfService', 'Concierge', 'Secretaria')
                THEN ver.operation_channel
            ELSE 'Others/Lost Tracking'
        END AS vb_channel
    FROM
        vb_events_raw AS ver
    WHERE
        ver.rn_visit = 1
),
vb_in_cohort AS (
    SELECT
        c.cohort_window_weeks,
        c.cohort_type,
        c.dt_cohort_start,
        c.dt_cohort_end,
        c.cohort_label,
        c.dt_bp,
        c.window_offset_days,
        vv.id_visit,
        vv.vb_channel
    FROM
        cohorts AS c
    INNER JOIN
        datalake_booking.booking AS bk
            ON CAST(bk.id_visitor AS STRING) = c.id_user
    INNER JOIN
        vb_visit AS vv
            ON vv.first_id_booking = bk.id
    WHERE
        CAST(
            FROM_UTC_TIMESTAMP(vv.first_vb_ts, 'America/Sao_Paulo') AS DATE
        ) BETWEEN c.dt_bp AND DATE_ADD(c.dt_bp, c.window_offset_days)
),
event_visit_level AS (
    SELECT
        vic.cohort_window_weeks,
        vic.cohort_type,
        vic.dt_cohort_start,
        vic.dt_cohort_end,
        vic.cohort_label,
        vic.vb_channel,
        vic.id_visit,
        MAX(
            CASE
                WHEN sde.event_name = 'VISIT_COMPLETED' THEN 1
                ELSE 0
            END
        ) AS is_vc
    FROM
        vb_in_cohort AS vic
    CROSS JOIN
        scan_bounds AS sb
    LEFT JOIN
        datalake_booking.booking AS bk2
            ON bk2.id_visit = vic.id_visit
    LEFT JOIN
        datalake_sale_demand_events.sale_demand_events AS sde
            ON sde.id_booking = bk2.id
            AND CAST(
                FROM_UTC_TIMESTAMP(sde.ts_event, 'America/Sao_Paulo') AS DATE
            ) BETWEEN vic.dt_bp AND DATE_ADD(
                vic.dt_bp,
                vic.window_offset_days
            )
            AND CAST(
                FROM_UTC_TIMESTAMP(sde.ts_event, 'America/Sao_Paulo') AS DATE
            ) BETWEEN sb.dt_history_start AND sb.dt_as_of
            AND sde.event_name = 'VISIT_COMPLETED'
    GROUP BY
        vic.cohort_window_weeks,
        vic.cohort_type,
        vic.dt_cohort_start,
        vic.dt_cohort_end,
        vic.cohort_label,
        vic.vb_channel,
        vic.id_visit
),
event_metrics AS (
    SELECT
        evl.cohort_window_weeks,
        evl.cohort_type,
        evl.dt_cohort_start,
        evl.dt_cohort_end,
        evl.cohort_label,
        COALESCE(evl.vb_channel, 'Consolidado') AS operation_channel,
        COUNT(*) AS event_anchored_vb_visits,
        SUM(evl.is_vc) AS event_anchored_vc_visits
    FROM
        event_visit_level AS evl
    GROUP BY GROUPING SETS (
        (
            evl.cohort_window_weeks,
            evl.cohort_type,
            evl.dt_cohort_start,
            evl.dt_cohort_end,
            evl.cohort_label,
            evl.vb_channel
        ),
        (
            evl.cohort_window_weeks,
            evl.cohort_type,
            evl.dt_cohort_start,
            evl.dt_cohort_end,
            evl.cohort_label
        )
    )
),
bp_level AS (
    SELECT
        c.cohort_window_weeks,
        c.cohort_type,
        c.dt_cohort_start,
        c.dt_cohort_end,
        c.cohort_label,
        c.operation_channel,
        c.id_user,
        COALESCE(v.vb_in_window, 0) AS vb_in_window,
        COALESCE(vo.vc_in_window, 0) AS vc_in_window,
        COALESCE(vo.is_os_in_window, 0) AS is_os_in_window,
        COALESCE(vo.os_in_window, 0) AS os_in_window,
        COALESCE(cc.ccv_in_window, 0) AS ccv_in_window,
        COALESCE(cc.is_ccv_in_window, 0) AS is_ccv_in_window,
        CASE
            WHEN COALESCE(vo.vc_in_window, 0) >= 3 THEN 1
            WHEN COALESCE(vo.vc_in_window, 0) BETWEEN 1 AND 2
                AND COALESCE(vo.is_os_in_window, 0) = 1 THEN 1
            ELSE 0
        END AS bes_flag,
        CASE
            WHEN COALESCE(vo.vc_in_window, 0) BETWEEN 1 AND 2
                AND COALESCE(vo.is_os_in_window, 0) = 1 THEN 1
            ELSE 0
        END AS os_no_3vc_flag
    FROM
        cohorts AS c
    LEFT JOIN
        vb_windowed AS v
            ON c.cohort_window_weeks = v.cohort_window_weeks
            AND c.cohort_type = v.cohort_type
            AND c.dt_cohort_start = v.dt_cohort_start
            AND c.dt_cohort_end = v.dt_cohort_end
            AND c.id_user = v.id_user
    LEFT JOIN
        vc_os_windowed AS vo
            ON c.cohort_window_weeks = vo.cohort_window_weeks
            AND c.cohort_type = vo.cohort_type
            AND c.dt_cohort_start = vo.dt_cohort_start
            AND c.dt_cohort_end = vo.dt_cohort_end
            AND c.id_user = vo.id_user
    LEFT JOIN
        ccv_windowed AS cc
            ON c.cohort_window_weeks = cc.cohort_window_weeks
            AND c.cohort_type = cc.cohort_type
            AND c.dt_cohort_start = cc.dt_cohort_start
            AND c.dt_cohort_end = cc.dt_cohort_end
            AND c.id_user = cc.id_user
),
final AS (
    SELECT
        bl.cohort_window_weeks,
        bl.cohort_type,
        bl.dt_cohort_start,
        bl.dt_cohort_end,
        bl.cohort_label,
        COALESCE(bl.operation_channel, 'Consolidado') AS operation_channel,
        COUNT(*) AS bp_count,
        SUM(bl.bes_flag) AS bes_users,
        CAST(SUM(bl.bes_flag) AS DOUBLE) / NULLIF(COUNT(*), 0) AS bes_rate,
        SUM(bl.vb_in_window) AS total_vbs,
        CAST(SUM(bl.vb_in_window) AS DOUBLE) / NULLIF(COUNT(*), 0) AS vb_per_bp,
        SUM(bl.vc_in_window) AS total_vcs,
        CAST(SUM(bl.vc_in_window) AS DOUBLE) / NULLIF(COUNT(*), 0) AS vc_per_bp,
        SUM(bl.os_in_window) AS total_os,
        SUM(bl.is_os_in_window) AS os_users,
        CAST(SUM(bl.is_os_in_window) AS DOUBLE) / NULLIF(COUNT(*), 0) AS bp2os,
        SUM(bl.ccv_in_window) AS total_ccvs,
        SUM(bl.is_ccv_in_window) AS ccv_users,
        CAST(SUM(bl.is_ccv_in_window) AS DOUBLE) / NULLIF(COUNT(*), 0) AS bp2ccv,
        SUM(bl.os_no_3vc_flag) AS os_no_3vc_users,
        CAST(SUM(bl.os_no_3vc_flag) AS DOUBLE) / NULLIF(COUNT(*), 0) AS os_no_3vc_rate
    FROM
        bp_level AS bl
    GROUP BY GROUPING SETS (
        (
            bl.cohort_window_weeks,
            bl.cohort_type,
            bl.dt_cohort_start,
            bl.dt_cohort_end,
            bl.cohort_label,
            bl.operation_channel
        ),
        (
            bl.cohort_window_weeks,
            bl.cohort_type,
            bl.dt_cohort_start,
            bl.dt_cohort_end,
            bl.cohort_label
        )
    )
)
SELECT
    DATE('{end_date}') AS dt_snapshot,
    f.cohort_window_weeks,
    f.cohort_type,
    f.dt_cohort_start,
    f.dt_cohort_end,
    f.cohort_label,
    f.operation_channel,
    f.bp_count,
    f.bes_users,
    f.bes_rate,
    f.total_vbs,
    f.vb_per_bp,
    f.total_vcs,
    f.vc_per_bp,
    f.total_os,
    f.os_users,
    f.bp2os,
    f.total_ccvs,
    f.ccv_users,
    f.bp2ccv,
    CASE
        WHEN f.cohort_type = 'LATEST_MATURE' THEN
            CONCAT(
                DATE_FORMAT(CAST(f.dt_cohort_start AS TIMESTAMP), 'dd/MM/yyyy'),
                '–',
                DATE_FORMAT(CAST(f.dt_cohort_end AS TIMESTAMP), 'dd/MM/yyyy')
            )
        ELSE DATE_FORMAT(CAST(f.dt_cohort_start AS TIMESTAMP), 'MMM-yy')
    END AS cohort_period,
    COALESCE(em.event_anchored_vb_visits, 0) AS event_anchored_vb_visits,
    COALESCE(em.event_anchored_vc_visits, 0) AS event_anchored_vc_visits,
    CAST(em.event_anchored_vc_visits AS DOUBLE)
        / NULLIF(em.event_anchored_vb_visits, 0) AS event_anchored_vb2vc,
    CAST(COALESCE(em.event_anchored_vb_visits, 0) AS DOUBLE)
        / NULLIF(f.bp_count, 0) AS event_anchored_vb_per_bp,
    CAST(COALESCE(em.event_anchored_vc_visits, 0) AS DOUBLE)
        / NULLIF(f.bp_count, 0) AS event_anchored_vc_per_bp,
    f.os_no_3vc_users,
    f.os_no_3vc_rate,
    YEAR(DATE('{end_date}')) AS year,
    MONTH(DATE('{end_date}')) AS month,
    DAY(DATE('{end_date}')) AS day
FROM
    final AS f
LEFT JOIN
    event_metrics AS em
        ON f.cohort_window_weeks = em.cohort_window_weeks
        AND f.cohort_type = em.cohort_type
        AND f.dt_cohort_start = em.dt_cohort_start
        AND f.dt_cohort_end = em.dt_cohort_end
        AND f.operation_channel = em.operation_channel
