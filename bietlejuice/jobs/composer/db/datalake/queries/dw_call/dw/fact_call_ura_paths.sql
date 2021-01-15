/******************************************************************************************************************
    The data migration from Asterisk to Teravoz and the integration with BigFone was completed in September 2019.
    Because of this, we are filtering all call data from that date.
******************************************************************************************************************/
WITH ura AS (
    SELECT DISTINCT
    *
    FROM
        datalake_bigfone_twilio.call_ura_events
    WHERE
        dt_event >= DATE('2019-09-01')
),
/*
    ura_interactions = time diff between the next event immediately after the ura event selected and ura event selected
    A call can have multiple ura events. So we find the pair (ura_event_selected, next_event_after_ura_event_selected) when:
    1. the events compared are different
    2. min(ts_next_event) >= ts_event_selected, and ts_next_event is the closest to ts_event_selected
    3. id_call is the same
*/
ura_interactions AS (
    SELECT
        ura_1.id,
        ura_1.id_call,
        ura_1.ts_created AS ts_created_ura_step_event,
        min(ura_2.ts_created) AS ts_created_next_ura_step_event
    FROM
        ura ura_1
    INNER JOIN
        ura ura_2
            ON ura_1.id_call=ura_2.id_call
            AND ura_1.ts_created <= ura_2.ts_created
            AND ura_1.id<>ura_2.id
    GROUP BY 1,2,3
)
SELECT
    u.id_call AS sk_call,
    CAST(u.id AS BIGINT) AS sk_flow_step,
    CAST(DATE_FORMAT(u.dt_event, 'YYYYMMDD') AS INT) AS sk_started,
    CAST(DATE_FORMAT(u.ts_created, 'YYYYMMDD') AS INT) AS sk_call_date,
    CAST(DATE_FORMAT(u.ts_created_local, 'YYYYMMDD') AS INT) AS sk_call_date_local,
    u.ura_step AS flow_step_name,
    u.name AS ura_step_name,
    u.digit_selection AS option_answered,
    (UNIX_TIMESTAMP(u2.ts_created_next_ura_step_event) - UNIX_TIMESTAMP(u2.ts_created_ura_step_event)) AS seconds_ura_step_duration,
    u.ts_created,
    u.ts_created_local,
    NOW() AS ts_load
FROM
    ura u
INNER JOIN
    ura_interactions u2
        ON u.id=u2.id