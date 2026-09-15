WITH voice_traces AS (
    SELECT
        trc.id_trace,
        trc.id_session AS id_langfuse_session,
        trc.year,
        trc.month,
        trc.day
    FROM
        datalake_langfuse_clean.traces AS trc
    WHERE
        ARRAY_CONTAINS(trc.tags, 'matthew')
        AND ARRAY_CONTAINS(trc.tags, 'online_call')
        AND trc.environment = 'prod'
        AND trc.id_session IS NOT NULL
        AND trc.ts_created >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
),
voice_obs AS (
    SELECT
        vt.id_langfuse_session,
        obs.id_observation,
        obs.id_parent_observation,
        obs.name,
        obs.output,
        obs.ts_started,
        obs.ts_ended,
        vt.year,
        vt.month,
        vt.day
    FROM
        datalake_langfuse_clean.observations AS obs
    INNER JOIN
        voice_traces AS vt
            ON vt.id_trace = obs.id_trace
    WHERE
        obs.ts_started >= TIMESTAMP('{load_start_date}') - INTERVAL 2 DAY
        AND obs.name IN (
            'user_speech',
            'input_speech_started',
            'input_speech_stopped',
            'input_audio_transcript',
            'generation',
            'output_audio_transcript',
            'tool_call',
            'vad_speech_started',
            'vad_barge_in_honored',
            'vad_backchannel_discarded',
            'agent_interrupt'
        )
),
/* Langfuse nests each turn's detail spans under the turn span itself, so the detail
   belongs to its parent observation and never to whichever turn happens to be open
   at the time: transcription completes asynchronously and routinely lands after the
   next turn started. */
user_speech_details AS (
    SELECT
        id_parent_observation,
        MIN(
            CASE
                WHEN name = 'input_speech_started' THEN ts_started
            END
        ) AS ts_speech_started,
        MIN(
            CASE
                WHEN name = 'input_speech_stopped' THEN ts_started
            END
        ) AS ts_speech_ended,
        MIN(
            CASE
                WHEN name = 'input_audio_transcript' THEN ts_started
            END
        ) AS ts_transcript,
        MIN(
            CASE
                WHEN name = 'input_audio_transcript'
                THEN NULLIF(TRIM(GET_JSON_OBJECT(output, '$.transcript')), '')
            END
        ) AS transcript
    FROM
        voice_obs
    WHERE
        name IN ('input_speech_started', 'input_speech_stopped', 'input_audio_transcript')
    GROUP BY
        id_parent_observation
),
user_speech AS (
    SELECT
        vo.id_langfuse_session,
        vo.id_observation,
        COALESCE(
            NULLIF(TRIM(GET_JSON_OBJECT(vo.output, '$.transcript')), ''),
            detail.transcript
        ) AS transcript,
        vo.ts_started,
        vo.ts_ended,
        COALESCE(detail.ts_speech_started, vo.ts_started) AS ts_speech_started,
        detail.ts_speech_ended,
        detail.ts_transcript,
        vo.year,
        vo.month,
        vo.day
    FROM
        voice_obs AS vo
    LEFT JOIN
        user_speech_details AS detail
            ON detail.id_parent_observation = vo.id_observation
    WHERE
        vo.name = 'user_speech'
),
agent_speech_details AS (
    SELECT
        id_parent_observation,
        MIN(
            CASE
                WHEN name = 'output_audio_transcript'
                THEN NULLIF(TRIM(GET_JSON_OBJECT(output, '$.transcript')), '')
            END
        ) AS transcript
    FROM
        voice_obs
    WHERE
        name = 'output_audio_transcript'
    GROUP BY
        id_parent_observation
),
/* agent_interrupt is a sibling of generation rather than a child, so it is attributed
   to the agent turn that opened before it: a running count of generation spans labels
   every row with its turn, and the flag is read off that partition. */
agent_turn_sequence AS (
    SELECT
        id_langfuse_session,
        id_observation,
        name,
        output,
        ts_started,
        ts_ended,
        year,
        month,
        day,
        SUM(
            CASE
                WHEN name = 'generation' THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_langfuse_session
            ORDER BY ts_started ASC, id_observation ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS agent_turn_index
    FROM
        voice_obs
    WHERE
        name IN ('generation', 'agent_interrupt')
),
agent_turns_flagged AS (
    SELECT
        id_langfuse_session,
        id_observation,
        name,
        output,
        ts_started,
        ts_ended,
        year,
        month,
        day,
        MAX(
            CASE
                WHEN name = 'agent_interrupt' THEN 1
                ELSE 0
            END
        ) OVER (
            PARTITION BY id_langfuse_session, agent_turn_index
        ) AS has_interrupt
    FROM
        agent_turn_sequence
),
agent_speech AS (
    SELECT
        turn.id_langfuse_session,
        turn.id_observation,
        COALESCE(
            detail.transcript,
            NULLIF(TRIM(GET_JSON_OBJECT(turn.output, '$.transcript')), '')
        ) AS transcript,
        CASE
            WHEN GET_JSON_OBJECT(turn.output, '$.status') = 'cancelled' THEN 1
            WHEN turn.has_interrupt = 1 THEN 1
            ELSE 0
        END AS flag_agent_interrupted,
        turn.ts_started,
        turn.ts_ended,
        turn.year,
        turn.month,
        turn.day
    FROM
        agent_turns_flagged AS turn
    LEFT JOIN
        agent_speech_details AS detail
            ON detail.id_parent_observation = turn.id_observation
    WHERE
        turn.name = 'generation'
),
/* The two-step VAD gate is a flat run of sibling spans, so the row following a
   vad_speech_started is either that start's outcome span or the next start. */
vad_sequence AS (
    SELECT
        id_langfuse_session,
        id_observation,
        name,
        ts_started,
        ts_ended,
        year,
        month,
        day,
        LEAD(name) OVER (
            PARTITION BY id_langfuse_session
            ORDER BY ts_started ASC, id_observation ASC
        ) AS next_vad_name,
        LEAD(ts_started) OVER (
            PARTITION BY id_langfuse_session
            ORDER BY ts_started ASC, id_observation ASC
        ) AS next_vad_ts_started
    FROM
        voice_obs
    WHERE
        name IN ('vad_speech_started', 'vad_barge_in_honored', 'vad_backchannel_discarded')
),
/* QA needs the utterance the gate was judging, which is the last user turn opened at
   or before the start: a running count of user turns puts each VAD start in the same
   partition as that turn. */
vad_speech_sequence AS (
    SELECT
        id_langfuse_session,
        id_observation,
        transcript,
        ts_started,
        1 AS is_user_speech,
        0 AS sort_priority
    FROM
        user_speech
    UNION ALL
    SELECT
        id_langfuse_session,
        id_observation,
        CAST(NULL AS STRING) AS transcript,
        ts_started,
        0 AS is_user_speech,
        1 AS sort_priority
    FROM
        vad_sequence
    WHERE
        name = 'vad_speech_started'
),
vad_speech_grouped AS (
    SELECT
        id_langfuse_session,
        id_observation,
        transcript,
        is_user_speech,
        SUM(is_user_speech) OVER (
            PARTITION BY id_langfuse_session
            ORDER BY ts_started ASC, sort_priority ASC, id_observation ASC
            ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        ) AS user_speech_index
    FROM
        vad_speech_sequence
),
vad_speech_carried AS (
    SELECT
        id_observation,
        MAX(
            CASE
                WHEN is_user_speech = 1 THEN transcript
            END
        ) OVER (
            PARTITION BY id_langfuse_session, user_speech_index
        ) AS transcript
    FROM
        vad_speech_grouped
),
vad AS (
    SELECT
        vad.id_langfuse_session,
        vad.id_observation,
        CASE
            WHEN vad.next_vad_name IN ('vad_barge_in_honored', 'vad_backchannel_discarded')
            THEN 'suppress'
            ELSE 'honor'
        END AS vad_first_decision,
        CASE
            WHEN vad.next_vad_name = 'vad_barge_in_honored' THEN 'barge_in_honored'
            WHEN vad.next_vad_name = 'vad_backchannel_discarded' THEN 'backchannel_discarded'
            ELSE 'honor_immediate'
        END AS vad_final_outcome,
        carried.transcript,
        vad.ts_started,
        vad.ts_ended,
        CASE
            WHEN vad.next_vad_name IN ('vad_barge_in_honored', 'vad_backchannel_discarded')
            THEN vad.next_vad_ts_started
        END AS ts_final_decision,
        vad.year,
        vad.month,
        vad.day
    FROM
        vad_sequence AS vad
    LEFT JOIN
        vad_speech_carried AS carried
            ON carried.id_observation = vad.id_observation
    WHERE
        vad.name = 'vad_speech_started'
),
all_events AS (
    SELECT
        id_langfuse_session,
        id_observation,
        'user_speech' AS event_type,
        CAST(NULL AS STRING) AS vad_first_decision,
        CAST(NULL AS STRING) AS vad_final_outcome,
        CAST(NULL AS STRING) AS tool_name,
        CAST(NULL AS STRING) AS tool_result,
        transcript,
        CASE
            WHEN transcript IS NULL OR TRIM(transcript) = '' THEN 1
            ELSE 0
        END AS is_empty_transcript,
        CAST(NULL AS INT) AS flag_failed_vad,
        CAST(NULL AS INT) AS flag_agent_interrupted,
        ts_started,
        ts_ended,
        ts_speech_started,
        ts_speech_ended,
        ts_transcript,
        CAST(NULL AS TIMESTAMP) AS ts_final_decision,
        year,
        month,
        day
    FROM
        user_speech
    UNION ALL
    SELECT
        id_langfuse_session,
        id_observation,
        'agent_speech' AS event_type,
        CAST(NULL AS STRING) AS vad_first_decision,
        CAST(NULL AS STRING) AS vad_final_outcome,
        CAST(NULL AS STRING) AS tool_name,
        CAST(NULL AS STRING) AS tool_result,
        transcript,
        CASE
            WHEN transcript IS NULL OR TRIM(transcript) = '' THEN 1
            ELSE 0
        END AS is_empty_transcript,
        CAST(NULL AS INT) AS flag_failed_vad,
        flag_agent_interrupted,
        ts_started,
        ts_ended,
        CAST(NULL AS TIMESTAMP) AS ts_speech_started,
        CAST(NULL AS TIMESTAMP) AS ts_speech_ended,
        CAST(NULL AS TIMESTAMP) AS ts_transcript,
        CAST(NULL AS TIMESTAMP) AS ts_final_decision,
        year,
        month,
        day
    FROM
        agent_speech
    UNION ALL
    SELECT
        id_langfuse_session,
        id_observation,
        'tool_call' AS event_type,
        CAST(NULL AS STRING) AS vad_first_decision,
        CAST(NULL AS STRING) AS vad_final_outcome,
        GET_JSON_OBJECT(output, '$.name') AS tool_name,
        GET_JSON_OBJECT(output, '$.output') AS tool_result,
        CAST(NULL AS STRING) AS transcript,
        CAST(NULL AS INT) AS is_empty_transcript,
        CAST(NULL AS INT) AS flag_failed_vad,
        CAST(NULL AS INT) AS flag_agent_interrupted,
        ts_started,
        ts_ended,
        CAST(NULL AS TIMESTAMP) AS ts_speech_started,
        CAST(NULL AS TIMESTAMP) AS ts_speech_ended,
        CAST(NULL AS TIMESTAMP) AS ts_transcript,
        CAST(NULL AS TIMESTAMP) AS ts_final_decision,
        year,
        month,
        day
    FROM
        voice_obs
    WHERE
        name = 'tool_call'
    UNION ALL
    SELECT
        id_langfuse_session,
        id_observation,
        'vad' AS event_type,
        vad_first_decision,
        vad_final_outcome,
        CAST(NULL AS STRING) AS tool_name,
        CAST(NULL AS STRING) AS tool_result,
        transcript,
        CASE
            WHEN transcript IS NULL OR TRIM(transcript) = '' THEN 1
            ELSE 0
        END AS is_empty_transcript,
        CASE
            WHEN vad_final_outcome = 'backchannel_discarded'
                AND transcript IS NOT NULL
                AND TRIM(transcript) <> ''
            THEN 1
            ELSE 0
        END AS flag_failed_vad,
        CAST(NULL AS INT) AS flag_agent_interrupted,
        ts_started,
        ts_ended,
        CAST(NULL AS TIMESTAMP) AS ts_speech_started,
        CAST(NULL AS TIMESTAMP) AS ts_speech_ended,
        CAST(NULL AS TIMESTAMP) AS ts_transcript,
        ts_final_decision,
        year,
        month,
        day
    FROM
        vad
)
SELECT
    id_langfuse_session,
    id_observation,
    event_type,
    CAST(
        ROW_NUMBER() OVER (
            PARTITION BY id_langfuse_session
            ORDER BY ts_started ASC, id_observation ASC
        ) AS INT
    ) AS event_index,
    vad_first_decision,
    vad_final_outcome,
    tool_name,
    tool_result,
    transcript,
    is_empty_transcript,
    flag_failed_vad,
    flag_agent_interrupted,
    ts_started,
    ts_ended,
    ts_speech_started,
    ts_speech_ended,
    ts_transcript,
    ts_final_decision,
    year,
    month,
    day
FROM
    all_events
