WITH app_events AS (
    SELECT
        TRY_CAST(REGEXP_REPLACE(e.id_user, '\\.', '') AS BIGINT) AS id_user,
        CASE GET_JSON_OBJECT(e.user_properties, '$.isMoraEnabledOnApp')
            WHEN 'true' THEN TRUE
            WHEN 'false' THEN FALSE
        END AS is_mora_enabled_on_app,
        e.ts_event
    FROM
        datalake_amplitude_clean.events AS e
    WHERE
        MAKE_DATE(e.year, e.month, e.day) >= DATE_SUB(DATE('{load_start_date}'), {days_lookback})
        AND e.id_app IN (170698, 183047)
        AND e.event_type IN (
            'search_page_viewed',
            'af_app_opened',
            'home_page_viewed',
            'login_page_viewed'
        )
        AND TRY_CAST(REGEXP_REPLACE(e.id_user, '\\.', '') AS BIGINT) IS NOT NULL
),

user_flags AS (
    SELECT
        ae.id_user,
        ae.is_mora_enabled_on_app,
        MAX(ae.ts_event) AS ts_last_event
    FROM
        app_events AS ae
    GROUP BY
        ae.id_user,
        ae.is_mora_enabled_on_app
)

SELECT
    uf.id_user,
    e.uuid_person,
    uf.is_mora_enabled_on_app,
    uf.ts_last_event
FROM
    user_flags AS uf
LEFT JOIN
    datalake_person.person_sks AS e
        ON e.id_user = CAST(uf.id_user AS STRING)
