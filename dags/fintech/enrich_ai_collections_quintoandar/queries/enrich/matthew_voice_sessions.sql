WITH voice_sessions AS (
    SELECT
        trc.id_trace,
        trc.id_session AS id_langfuse_session,
        GET_JSON_OBJECT(trc.output, '$.call_sid') AS id_twilio_call,
        attempt.state AS call_attempt_state,
        trc.ts_created AS ts_trace_created,
        vs.ts_started AS ts_call_started,
        vs.ts_ended AS ts_call_ended,
        TRY_CAST(GET_JSON_OBJECT(vs.call_context, '$.numberOfOpenDebts') AS INT) AS n_open_debts,
        TRY_CAST(GET_JSON_OBJECT(vs.call_context, '$.totalOpenDebtsValue') AS DECIMAL(18, 2)) AS open_debts_amount,
        TO_DATE(GET_JSON_OBJECT(vs.call_context, '$.oldestDebtsDueDate')) AS dt_oldest_debt_due,
        CASE WHEN LOWER(GET_JSON_OBJECT(vs.call_context, '$.hasDiscountFinesFees')) = 'true' THEN 1 ELSE 0 END AS has_discount_fines_fees,
        CASE WHEN LOWER(GET_JSON_OBJECT(vs.call_context, '$.hasNegotiationAvailable')) = 'true' THEN 1 ELSE 0 END AS has_negotiation_available,
        CASE WHEN LOWER(GET_JSON_OBJECT(vs.call_context, '$.hasPixBoletoInstallments')) = 'true' THEN 1 ELSE 0 END AS has_pix_boleto_installments,
        CASE WHEN LOWER(GET_JSON_OBJECT(vs.call_context, '$.hasCreditCardInstallments')) = 'true' THEN 1 ELSE 0 END AS has_credit_card_installments,
        trc.year,
        trc.month,
        trc.day
    FROM
        datalake_langfuse_clean.traces AS trc
    LEFT JOIN
        datalake_copilot_service_clean.voice_call_attempt AS attempt
            ON attempt.id_voice_call_external = trc.id_session
    LEFT JOIN
        datalake_copilot_service_clean.voice_session AS vs
            ON vs.id = attempt.id_voice_session
    WHERE
        ARRAY_CONTAINS(trc.tags, 'matthew')
        AND ARRAY_CONTAINS(trc.tags, 'online_call')
        AND trc.environment = 'prod'
        AND trc.id_session IS NOT NULL
        AND MAKE_DATE(trc.year, trc.month, trc.day) >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND trc.ts_created >= TIMESTAMP('{load_start_date}')
),
session_events AS (
    SELECT
        e.id_langfuse_session,
        e.event_type,
        e.event_index,
        e.vad_first_decision,
        e.vad_final_outcome,
        e.tool_name,
        e.tool_result,
        e.is_empty_transcript,
        e.flag_failed_vad,
        e.flag_agent_interrupted,
        e.ts_started
    FROM
        datalake_ai_collections_quintoandar.matthew_voice_events AS e
    INNER JOIN
        voice_sessions AS vs
            ON vs.id_langfuse_session = e.id_langfuse_session
    WHERE
        MAKE_DATE(e.year, e.month, e.day) >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND e.ts_started >= TIMESTAMP('{load_start_date}')
),
event_metrics AS (
    SELECT
        se.id_langfuse_session,
        COUNT(CASE WHEN se.event_type = 'user_speech' THEN 1 END) AS n_user_speech_events,
        COUNT(CASE WHEN se.event_type = 'agent_speech' THEN 1 END) AS n_agent_speech_events,
        SUM(CASE WHEN se.event_type = 'user_speech' AND se.is_empty_transcript = 1 THEN 1 ELSE 0 END) AS n_empty_user_transcripts,
        COUNT(CASE WHEN se.event_type = 'vad' THEN 1 END) AS n_vad_starts,
        SUM(CASE WHEN se.event_type = 'vad' AND se.vad_first_decision = 'honor' THEN 1 ELSE 0 END) AS n_vad_first_honor,
        SUM(CASE WHEN se.event_type = 'vad' AND se.vad_first_decision = 'suppress' THEN 1 ELSE 0 END) AS n_vad_first_suppress,
        SUM(CASE WHEN se.event_type = 'vad' AND se.vad_final_outcome = 'backchannel_discarded' THEN 1 ELSE 0 END) AS n_vad_discarded,
        SUM(CASE WHEN se.event_type = 'vad' AND se.flag_failed_vad = 1 THEN 1 ELSE 0 END) AS n_failed_vad,
        SUM(CASE WHEN se.event_type = 'agent_speech' AND se.flag_agent_interrupted = 1 THEN 1 ELSE 0 END) AS n_agent_interrupts,
        COUNT(CASE WHEN se.event_type = 'tool_call' THEN 1 END) AS n_tool_calls,
        MAX(
            CASE
                WHEN se.event_type = 'user_speech'
                    AND se.is_empty_transcript = 0
                THEN 1
                ELSE 0
            END
        ) AS flag_user_spoke,
        MAX(
            CASE
                WHEN se.tool_name = 'analyze_payment_allegation_date' THEN 1
                ELSE 0
            END
        ) AS flag_payment_allegation,
        MIN(se.ts_started) AS ts_first_event,
        MAX(se.ts_started) AS ts_last_event
    FROM
        session_events AS se
    GROUP BY
        se.id_langfuse_session
),
/* event_index already ranks the call by (ts_started, id_observation), so the highest
   index among the identity calls is the last one the agent made. */
identity_metrics AS (
    SELECT
        se.id_langfuse_session,
        COUNT(*) AS n_identity_check_calls,
        MAX_BY(se.tool_result, se.event_index) AS last_identity_tool_result
    FROM
        session_events AS se
    WHERE
        se.tool_name = 'confirm_user_identity_tool'
    GROUP BY
        se.id_langfuse_session
),
event_streaks AS (
    SELECT
        se.id_langfuse_session,
        se.event_type,
        se.event_index - ROW_NUMBER() OVER (
            PARTITION BY se.id_langfuse_session, se.event_type
            ORDER BY se.event_index ASC
        ) AS streak_group
    FROM
        session_events AS se
    WHERE
        se.event_type IN ('user_speech', 'agent_speech')
),
event_streak_lengths AS (
    SELECT
        es.id_langfuse_session,
        es.event_type,
        COUNT(*) AS streak_len
    FROM
        event_streaks AS es
    GROUP BY
        es.id_langfuse_session,
        es.event_type,
        es.streak_group
),
streak_metrics AS (
    SELECT
        esl.id_langfuse_session,
        MAX(CASE WHEN esl.event_type = 'user_speech' THEN esl.streak_len END) AS n_consecutive_user_turns,
        MAX(CASE WHEN esl.event_type = 'agent_speech' THEN esl.streak_len END) AS n_consecutive_agent_turns
    FROM
        event_streak_lengths AS esl
    GROUP BY
        esl.id_langfuse_session
),
error_metrics AS (
    SELECT
        vs.id_langfuse_session,
        COUNT(*) AS n_error_observations
    FROM
        datalake_langfuse_clean.observations AS obs
    INNER JOIN
        voice_sessions AS vs
            ON vs.id_trace = obs.id_trace
    WHERE
        obs.name = 'error'
        AND MAKE_DATE(obs.year, obs.month, obs.day) >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND obs.ts_started >= TIMESTAMP('{load_start_date}')
    GROUP BY
        vs.id_langfuse_session
),
/* The wrapping span is the earliest observation on the trace and parents every turn,
   so its latency is the dial duration in seconds. Copilot voice_session timestamps
   are campaign-grain and cannot be used for it. */
call_span AS (
    SELECT
        vs.id_langfuse_session,
        MIN_BY(obs.latency, obs.ts_started) AS call_duration
    FROM
        datalake_langfuse_clean.observations AS obs
    INNER JOIN
        voice_sessions AS vs
            ON vs.id_trace = obs.id_trace
    WHERE
        MAKE_DATE(obs.year, obs.month, obs.day) >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND obs.ts_started >= TIMESTAMP('{load_start_date}')
    GROUP BY
        vs.id_langfuse_session
),
/* Online evaluation only judges a sample of the calls (~7% of dials), so the judge
   flag is derived from the presence of a MatthewVoiceTag* score rather than from the
   session existing: outside the sample every eval_* stays NULL by absence. */
voice_scores AS (
    SELECT
        s.id_session AS id_langfuse_session,
        MAX(CASE WHEN s.name LIKE 'MatthewVoiceTag%' THEN 1 ELSE 0 END) AS has_llm_voice_tags,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagCallAnswered' THEN CAST(s.value AS INT) END) AS eval_call_answered,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagCallEndedByVoiceMail' THEN CAST(s.value AS INT) END) AS eval_call_ended_by_voice_mail,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserPersonNameChecked' THEN CAST(s.value AS INT) END) AS eval_user_person_name_checked,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserIdentityChecked' THEN CAST(s.value AS INT) END) AS eval_user_identity_checked,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserRefusedToCheckIdentity' THEN CAST(s.value AS INT) END) AS eval_user_refused_to_check_identity,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserAcknowledgedDebt' THEN CAST(s.value AS INT) END) AS eval_user_acknowledged_debt,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserAlreadyPaid' THEN CAST(s.value AS INT) END) AS eval_user_already_paid,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserCommitedToPayment' THEN CAST(s.value AS INT) END) AS eval_user_committed_to_payment,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagNegotiationInvoice' THEN CAST(s.value AS INT) END) AS eval_negotiation_invoice,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagNegotiationCreditCard' THEN CAST(s.value AS INT) END) AS eval_negotiation_credit_card,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserRequestedPix' THEN CAST(s.value AS INT) END) AS eval_user_requested_pix,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserRefusedNegotiation' THEN CAST(s.value AS INT) END) AS eval_user_refused_negotiation,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserRequestedHumanSupport' THEN CAST(s.value AS INT) END) AS eval_user_requested_human_support,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagRequestedHelpToNavigateApp' THEN CAST(s.value AS INT) END) AS eval_requested_help_to_navigate_app,
        MAX(CASE WHEN s.name = 'MatthewVoiceTagUserRequestedOptOut' THEN CAST(s.value AS INT) END) AS eval_user_requested_opt_out
    FROM
        datalake_langfuse_clean.scores AS s
    INNER JOIN
        voice_sessions AS vs
            ON vs.id_langfuse_session = s.id_session
    WHERE
        s.name LIKE 'MatthewVoiceTag%'
        AND MAKE_DATE(s.year, s.month, s.day) >= DATE('{load_start_date}') - INTERVAL 1 DAY
        AND s.ts_created >= TIMESTAMP('{load_start_date}')
    GROUP BY
        s.id_session
)
SELECT
    vs.id_langfuse_session,
    vs.id_twilio_call,
    vs.call_attempt_state,
    vs.open_debts_amount,
    vs.n_open_debts,
    cs.call_duration,
    COALESCE(im.n_identity_check_calls, 0) AS n_identity_check_calls,
    COALESCE(em.n_user_speech_events, 0) AS n_user_speech_events,
    COALESCE(em.n_agent_speech_events, 0) AS n_agent_speech_events,
    COALESCE(em.n_empty_user_transcripts, 0) AS n_empty_user_transcripts,
    COALESCE(em.n_vad_starts, 0) AS n_vad_starts,
    COALESCE(em.n_vad_first_honor, 0) AS n_vad_first_honor,
    COALESCE(em.n_vad_first_suppress, 0) AS n_vad_first_suppress,
    COALESCE(em.n_vad_discarded, 0) AS n_vad_discarded,
    COALESCE(em.n_failed_vad, 0) AS n_failed_vad,
    COALESCE(em.n_agent_interrupts, 0) AS n_agent_interrupts,
    COALESCE(em.n_tool_calls, 0) AS n_tool_calls,
    COALESCE(sm.n_consecutive_user_turns, 0) AS n_consecutive_user_turns,
    COALESCE(sm.n_consecutive_agent_turns, 0) AS n_consecutive_agent_turns,
    COALESCE(err.n_error_observations, 0) AS n_error_observations,
    sc.eval_call_answered,
    sc.eval_call_ended_by_voice_mail,
    sc.eval_user_person_name_checked,
    sc.eval_user_identity_checked,
    sc.eval_user_refused_to_check_identity,
    sc.eval_user_acknowledged_debt,
    sc.eval_user_already_paid,
    sc.eval_user_committed_to_payment,
    sc.eval_negotiation_invoice,
    sc.eval_negotiation_credit_card,
    sc.eval_user_requested_pix,
    sc.eval_user_refused_negotiation,
    sc.eval_user_requested_human_support,
    sc.eval_requested_help_to_navigate_app,
    sc.eval_user_requested_opt_out,
    vs.has_discount_fines_fees,
    vs.has_negotiation_available,
    vs.has_pix_boleto_installments,
    vs.has_credit_card_installments,
    COALESCE(sc.has_llm_voice_tags, 0) AS has_llm_voice_tags,
    CASE WHEN vs.call_attempt_state = 'ANSWERED' THEN 1 ELSE 0 END AS flag_call_answered,
    COALESCE(em.flag_user_spoke, 0) AS flag_user_spoke,
    CASE WHEN vs.call_attempt_state = 'ANSWERED_BY_MACHINE' THEN 1 ELSE 0 END AS flag_answered_by_machine,
    CASE WHEN COALESCE(im.n_identity_check_calls, 0) > 0 THEN 1 ELSE 0 END AS flag_identity_check_triggered,
    CASE
        WHEN im.last_identity_tool_result LIKE '%is correct%' THEN 1
        WHEN im.last_identity_tool_result LIKE '%is incorrect%' THEN 0
        ELSE NULL
    END AS flag_identity_check_result,
    COALESCE(em.flag_payment_allegation, 0) AS flag_payment_allegation,
    vs.dt_oldest_debt_due,
    vs.ts_trace_created,
    vs.ts_call_started,
    vs.ts_call_ended,
    em.ts_first_event,
    em.ts_last_event,
    vs.year,
    vs.month,
    vs.day
FROM
    voice_sessions AS vs
LEFT JOIN
    event_metrics AS em
        ON em.id_langfuse_session = vs.id_langfuse_session
LEFT JOIN
    identity_metrics AS im
        ON im.id_langfuse_session = vs.id_langfuse_session
LEFT JOIN
    streak_metrics AS sm
        ON sm.id_langfuse_session = vs.id_langfuse_session
LEFT JOIN
    error_metrics AS err
        ON err.id_langfuse_session = vs.id_langfuse_session
LEFT JOIN
    call_span AS cs
        ON cs.id_langfuse_session = vs.id_langfuse_session
LEFT JOIN
    voice_scores AS sc
        ON sc.id_langfuse_session = vs.id_langfuse_session
