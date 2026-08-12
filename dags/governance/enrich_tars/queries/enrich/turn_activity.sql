-- One row per Tars turn, combining turn_metrics (latency/outcome from turn_end)
-- with turn_quality (dq/confidence from turn_summary/turn_blocked) via a FULL
-- OUTER JOIN on id_turn. Neither side is guaranteed present for every turn:
-- turn_end is currently forno-only (env=forno), so in prod rows come from
-- turn_quality alone with null latency columns until turn_end reaches prod.
-- Rows where id_turn could not be resolved on the source event (synthetic
-- fallback ids differ between turn_metrics and turn_quality) will not match
-- across the join and surface as two separate rows, same as today.
WITH metrics AS (
    SELECT
        id_turn,
        id_session,
        session_source,
        turn_index,
        outcome,
        start_source,
        trigger,
        duration_ms AS metrics_duration_ms,
        ts_turn_end,
        dt_turn AS dt_turn_metrics,
        year AS year_metrics,
        month AS month_metrics,
        day AS day_metrics
    FROM
        datalake_tars.turn_metrics
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
),
quality AS (
    SELECT
        id_turn,
        id_session,
        event_type,
        session_source AS quality_session_source,
        response_category,
        business_domain,
        answer_confidence_tier,
        dq_status,
        is_schema_gate_passed,
        blocking_step,
        error_class,
        duration_ms AS quality_duration_ms,
        ts_turn,
        dt_turn AS dt_turn_quality,
        year AS year_quality,
        month AS month_quality,
        day AS day_quality
    FROM
        datalake_tars.turn_quality
    WHERE
        MAKE_DATE(year, month, day) BETWEEN "{load_start_date}"
        AND "{load_end_date}"
)
SELECT
    COALESCE(m.id_turn, q.id_turn) AS id_turn,
    COALESCE(m.id_session, q.id_session) AS id_session,
    COALESCE(m.session_source, q.quality_session_source, 'unknown') AS session_source,
    q.event_type,
    m.outcome,
    m.start_source,
    m.trigger,
    COALESCE(m.metrics_duration_ms, q.quality_duration_ms) AS duration_ms,
    q.response_category,
    q.business_domain,
    q.answer_confidence_tier,
    q.dq_status,
    q.is_schema_gate_passed,
    q.blocking_step,
    q.error_class,
    m.turn_index,
    COALESCE(q.ts_turn, m.ts_turn_end) AS ts_turn,
    COALESCE(q.dt_turn_quality, m.dt_turn_metrics) AS dt_turn,
    COALESCE(q.year_quality, m.year_metrics) AS year,
    COALESCE(q.month_quality, m.month_metrics) AS month,
    COALESCE(q.day_quality, m.day_metrics) AS day
FROM
    metrics AS m
FULL OUTER JOIN
    quality AS q
        ON m.id_turn = q.id_turn
