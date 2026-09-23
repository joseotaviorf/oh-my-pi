WITH app_events AS (
    SELECT
        TRY_CAST(REGEXP_REPLACE(e.id_user, '\\.', '') AS BIGINT) AS id_user,
        CASE GET_JSON_OBJECT(e.user_properties, '$.isMoraEnabledOnApp')
            WHEN 'true' THEN TRUE
            WHEN 'false' THEN FALSE
        END AS is_mora_enabled_on_app,
        MAKE_DATE(e.year, e.month, e.day) AS dt_event,
        e.ts_event
    FROM
        datalake_amplitude_clean.events AS e
    WHERE
        MAKE_DATE(e.year, e.month, e.day) >= DATE_SUB(DATE('{load_start_date}'), {days_lookback} - 1)
        AND MAKE_DATE(e.year, e.month, e.day) <= DATE('{load_end_date}')
        AND e.id_app IN (170698, 183047)
        AND e.event_type IN (
            'search_page_viewed',
            'af_app_opened',
            'home_page_viewed',
            'login_page_viewed'
        )
        AND TRY_CAST(REGEXP_REPLACE(e.id_user, '\\.', '') AS BIGINT) IS NOT NULL
),

daily_events AS (
    SELECT
        ae.id_user,
        ae.is_mora_enabled_on_app,
        ae.dt_event,
        ae.ts_event,
        ROW_NUMBER() OVER (
            PARTITION BY
                ae.id_user,
                ae.dt_event
            ORDER BY
                ae.ts_event DESC,
                ae.is_mora_enabled_on_app DESC
        ) AS rn
    FROM
        app_events AS ae
),

user_flags AS (
    SELECT
        de.id_user,
        de.is_mora_enabled_on_app,
        sd.dt_snapshot,
        de.ts_event AS ts_last_event,
        ROW_NUMBER() OVER (
            PARTITION BY
                de.id_user,
                sd.dt_snapshot
            ORDER BY
                de.ts_event DESC,
                de.is_mora_enabled_on_app DESC
        ) AS rn
    FROM
        daily_events AS de
    LATERAL VIEW EXPLODE(
        SEQUENCE(
            GREATEST(de.dt_event, DATE('{load_start_date}')),
            LEAST(DATE_ADD(de.dt_event, {days_lookback} - 1), DATE('{load_end_date}'))
        )
    ) sd AS dt_snapshot
    WHERE
        de.rn = 1
)

SELECT
    uf.id_user,
    e.uuid_person,
    uf.is_mora_enabled_on_app,
    uf.dt_snapshot,
    uf.ts_last_event
FROM
    user_flags AS uf
LEFT JOIN
    datalake_person.person_sks AS e
        ON e.id_user = CAST(uf.id_user AS STRING)
WHERE
    uf.rn = 1
