/******************************************************************************************************************
    The data migration FROM Asterisk to Teravoz and the integration WITH BigFone was completed in September 2019.
    Because of this, we are filtering all call data FROM that DATE.
******************************************************************************************************************/
WITH call_events AS (
    SELECT
        *
    FROM
        datalake_bigfone_events.events
    WHERE
        DATE(
            CONCAT(
                CAST(YEAR AS VARCHAR(4)), '-',
                CAST(MONTH AS VARCHAR(2)), '-',
                CAST(DAY AS VARCHAR(2))
            )
        )>= DATE('2019-09-01')
),
calls AS (
    SELECT DISTINCT
        id_call
    FROM
        call_events
),
call_context_data AS (
    SELECT
        id_call,
        call_direction,
        quinto_andar_number,
        incoming_phone_number,
        incoming_phone_type
    FROM
        datalake_bigfone_twilio.call_context_data
    GROUP BY 1,2,3,4,5
),
calls_recording AS (
    SELECT
        id_call,
        recording_url
    FROM
        datalake_bigfone_twilio.call_recording_available_events
    WHERE
        dt_event >= DATE('2019-09-01')
    GROUP BY 1,2
),
-- gets the user dialed phone (open column values for typing)
dialed_phone AS (
    SELECT
        id_call,
        phone
    FROM
        datalake_bigfone_twilio.dialed_phone
    GROUP BY 1,2
)
SELECT
    c.id_call AS sk_call,
    ccd.incoming_phone_type AS external_phone_type,
    ccd.call_direction AS direction,
    CASE
        WHEN ccd.call_direction='inbound' THEN  ccd.quinto_andar_number
        WHEN ccd.call_direction='outbound' THEN ccd.incoming_phone_number
        WHEN ccd.call_direction='internal' THEN ccd.incoming_phone_number
    END AS called_phone_number,
    CASE
        WHEN ccd.call_direction='inbound' THEN  ccd.incoming_phone_number
        WHEN ccd.call_direction='outbound' THEN ccd.quinto_andar_number
        WHEN ccd.call_direction='internal' THEN ccd.quinto_andar_number
    END AS caller_phone_number,
    ccd.incoming_phone_number AS external_phone_number,
    dp.phone AS user_dialed_phone_number,
    cr.recording_url AS recording_url,
    NOW() AS ts_load
FROM calls c
    LEFT JOIN
        call_context_data ccd
            ON c.id_call=ccd.id_call
    LEFT JOIN
        calls_recording cr
            ON c.id_call=cr.id_call
    LEFT JOIN
        dialed_phone dp
            ON c.id_call=dp.id_call