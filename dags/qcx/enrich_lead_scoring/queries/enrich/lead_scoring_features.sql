-- ================================================================
-- CRM qualifier features for Consórcio Behavioral Lead Scoring
-- Grain: one row per deal (id_deal) in the lead_scoring_population
-- partition of the same spec_version
-- Conrado Qualificador answers from datalake_consorcio.deal.
-- All five qualifier fields are mapped to canonical labels or null
-- when unanswered. investment_type is renda_ou_patrimonio / revenda /
-- other (~80 filled rows in spec_version 1). Simulation features count
-- and take the last credit_value strictly before ts_handoff (UTC converted
-- to America/Sao_Paulo). Join is simulation.id_lead = lead.id (same as
-- deal.total_simulations). Blip-era rows almost never fill lead_id;
-- PlatConv does. Null ts_handoff yields null count and null value;
-- handoff with no linked sim yields 0 / null.
-- n_lead_turns counts human speaker-runs (not messages) before ts_handoff
-- on Blip and PlatConv separately; combined prefers PlatConv when that
-- log exists. n_lead_turns_post_simulation is the same count after the last
-- pre-handoff simulation (null when there is no simulation).
-- seconds_bot_turn_to_lead_reply is the median seconds from the
-- end of a bot turn to the start of the next lead turn. is_user_initiated
-- is true when the lead opened WhatsApp, false when the company sent the
-- C2W / abandoned-cart template, null when HubSpot did not set the flag
-- (typical before 2026-08-10). Not inferred from first chat speaker.
-- ================================================================
WITH qualifier_source AS (
  SELECT
    population.id_deal,
    population.ts_handoff,
    LOWER(TRIM(consorcio_deal.qualifier_goal)) AS goal_key,
    LOWER(TRIM(consorcio_deal.qualifier_investment_type)) AS investment_type_key,
    LOWER(TRIM(consorcio_deal.qualifier_reason)) AS reason_key,
    LOWER(TRIM(consorcio_deal.qualifier_knowledge)) AS knowledge_key,
    LOWER(TRIM(consorcio_deal.qualifier_urgency)) AS urgency_key,
    CASE
      WHEN consorcio_deal.contact_type = 'user_initiated' THEN TRUE
      WHEN consorcio_deal.contact_type = 'company_initiated' THEN FALSE
    END AS is_user_initiated
  FROM
    datalake_consorcio.lead_scoring_population AS population
  INNER JOIN
    datalake_consorcio.deal AS consorcio_deal
      ON consorcio_deal.id_deal = population.id_deal
  WHERE
    population.spec_version = {spec_version}
),
qualifier_normalized AS (
  SELECT
    qualifier_source.id_deal,
    qualifier_source.ts_handoff,
    CASE
      WHEN qualifier_source.goal_key IS NULL
        OR qualifier_source.goal_key = ''
        OR qualifier_source.goal_key IN (
          'não informado',
          'nao informado',
          'indefinido',
          'a definir',
          'a descobrir',
          'a confirmar',
          'tbd',
          'undefined',
          'unknown',
          'ainda não informado',
          'ainda nao informado',
          'simulação',
          'simulacao'
        )
        OR qualifier_source.goal_key LIKE 'aguardando%'
        OR qualifier_source.goal_key LIKE '%não informado%'
        OR qualifier_source.goal_key LIKE '%nao informado%'
        THEN NULL
      WHEN qualifier_source.goal_key IN ('moradia', 'morar', 'casa própria', 'casa propria')
        THEN 'moradia'
      WHEN (
          qualifier_source.goal_key LIKE 'moradia%'
          OR qualifier_source.goal_key LIKE 'morar%'
        )
        AND qualifier_source.goal_key NOT LIKE '%invest%'
        THEN 'moradia'
      WHEN qualifier_source.goal_key IN ('investimento', 'investir')
        THEN 'investimento'
      WHEN (
          qualifier_source.goal_key LIKE 'investimento%'
          OR qualifier_source.goal_key LIKE 'investir%'
        )
        AND qualifier_source.goal_key NOT LIKE '%morad%'
        AND qualifier_source.goal_key NOT LIKE '%morar%'
        THEN 'investimento'
      ELSE 'other'
    END AS qualifier_goal,
    CASE
      WHEN qualifier_source.investment_type_key IS NULL
        OR qualifier_source.investment_type_key = ''
        OR qualifier_source.investment_type_key IN (
          'não informado',
          'nao informado',
          'indefinido',
          'a definir',
          'a descobrir',
          'a confirmar',
          'tbd',
          'undefined',
          'unknown',
          'ainda não definiu',
          'ainda nao definiu',
          'sem estratégia definida',
          'sem estrategia definida'
        )
        OR qualifier_source.investment_type_key LIKE 'aguardando%'
        OR qualifier_source.investment_type_key LIKE '%não informado%'
        OR qualifier_source.investment_type_key LIKE '%nao informado%'
        THEN NULL
      WHEN (
          qualifier_source.investment_type_key LIKE '%alug%'
          OR qualifier_source.investment_type_key LIKE '%renda%'
        )
        AND qualifier_source.investment_type_key LIKE '%revend%'
        THEN 'other'
      WHEN qualifier_source.investment_type_key LIKE '%alug%'
        OR qualifier_source.investment_type_key LIKE '%renda%'
        OR qualifier_source.investment_type_key LIKE '%airbnb%'
        OR qualifier_source.investment_type_key LIKE '%patrim%'
        OR qualifier_source.investment_type_key LIKE '%diversif%'
        OR qualifier_source.investment_type_key LIKE '%comercial%'
        THEN 'renda_ou_patrimonio'
      WHEN qualifier_source.investment_type_key LIKE '%revend%'
        OR qualifier_source.investment_type_key LIKE '%para vender%'
        THEN 'revenda'
      ELSE 'other'
    END AS qualifier_investment_type,
    CASE
      WHEN qualifier_source.reason_key IS NULL
        OR qualifier_source.reason_key = ''
        OR qualifier_source.reason_key IN (
          'não informado',
          'nao informado',
          'indefinido',
          'a definir',
          'a descobrir',
          'a confirmar',
          'tbd',
          'undefined',
          'unknown',
          'ainda não informado',
          'ainda nao informado'
        )
        OR qualifier_source.reason_key LIKE 'aguardando%'
        OR qualifier_source.reason_key LIKE '%não informado%'
        OR qualifier_source.reason_key LIKE '%nao informado%'
        THEN NULL
      WHEN qualifier_source.reason_key LIKE '%para alugar%'
        OR qualifier_source.reason_key LIKE '%pra alugar%'
        OR qualifier_source.reason_key LIKE '%renda%'
        OR qualifier_source.reason_key LIKE '%patrim%'
        OR qualifier_source.reason_key LIKE '%invest%'
        OR qualifier_source.reason_key LIKE '%valoriza%'
        OR qualifier_source.reason_key LIKE '%revenda%'
        THEN 'investimento'
      WHEN qualifier_source.reason_key LIKE '%alug%'
        OR qualifier_source.reason_key LIKE '%locação%'
        OR qualifier_source.reason_key LIKE '%locacao%'
        OR qualifier_source.reason_key LIKE '%quitar%'
        OR qualifier_source.reason_key LIKE '%financi%'
        OR qualifier_source.reason_key LIKE '%juros%'
        THEN 'aluguel_ou_divida'
      WHEN qualifier_source.reason_key IN ('pais', 'favor', 'morar')
        OR qualifier_source.reason_key LIKE '%dos pais%'
        OR qualifier_source.reason_key LIKE '%os pais%'
        OR qualifier_source.reason_key LIKE '%com pais%'
        OR qualifier_source.reason_key LIKE '%independ%'
        OR qualifier_source.reason_key LIKE '%de favor%'
        OR qualifier_source.reason_key LIKE '%do favor%'
        OR qualifier_source.reason_key LIKE '%familiar%'
        OR qualifier_source.reason_key LIKE '%família%'
        OR qualifier_source.reason_key LIKE '%familia%'
        OR qualifier_source.reason_key LIKE '%mãe%'
        OR qualifier_source.reason_key LIKE '%mae%'
        OR qualifier_source.reason_key LIKE '%própri%'
        OR qualifier_source.reason_key LIKE '%propri%'
        OR qualifier_source.reason_key LIKE '%moradia%'
        OR (
          qualifier_source.reason_key LIKE '%casa%'
          AND qualifier_source.reason_key NOT LIKE '%casamento%'
        )
        OR qualifier_source.reason_key LIKE '%constru%'
        OR qualifier_source.reason_key LIKE '%primeiro imóvel%'
        OR qualifier_source.reason_key LIKE '%primeiro imovel%'
        OR qualifier_source.reason_key LIKE '%garantir um imóvel%'
        OR qualifier_source.reason_key LIKE '%garantir um imovel%'
        THEN 'casa_propria'
      ELSE 'other'
    END AS qualifier_reason,
    CASE
      WHEN qualifier_source.knowledge_key IS NULL
        OR qualifier_source.knowledge_key = ''
        OR qualifier_source.knowledge_key IN (
          'não informado',
          'nao informado',
          'indefinido',
          'a definir',
          'a descobrir',
          'a confirmar',
          'tbd',
          'undefined',
          'unknown',
          'ambíguo',
          'ambiguo',
          'ainda não informado',
          'ainda nao informado'
        )
        OR qualifier_source.knowledge_key LIKE 'aguardando%'
        OR qualifier_source.knowledge_key LIKE '%não informado%'
        OR qualifier_source.knowledge_key LIKE '%nao informado%'
        THEN NULL
      WHEN qualifier_source.knowledge_key LIKE '%leigo%'
        AND qualifier_source.knowledge_key LIKE '%experiente%'
        THEN NULL
      WHEN qualifier_source.knowledge_key LIKE '%leigo%'
        OR qualifier_source.knowledge_key LIKE '%leiga%'
        OR qualifier_source.knowledge_key LIKE '%intermedi%'
        OR qualifier_source.knowledge_key IN (
          'conhecedor',
          'conhece um pouco',
          'conhece o básico',
          'conhece o basico',
          'básico',
          'basico',
          'semi-leigo',
          'noção básica',
          'nocao basica',
          'baixo',
          'parcial',
          'primeiro investimento'
        )
        OR qualifier_source.knowledge_key LIKE 'conhece um pouco%'
        OR qualifier_source.knowledge_key LIKE 'conhece o básico%'
        OR qualifier_source.knowledge_key LIKE 'conhece o basico%'
        OR qualifier_source.knowledge_key LIKE '%conhecimento básico%'
        OR qualifier_source.knowledge_key LIKE '%conhecimento basico%'
        OR qualifier_source.knowledge_key LIKE '%noção básica%'
        OR qualifier_source.knowledge_key LIKE '%leve conhecimento%'
        THEN 'leigo'
      WHEN qualifier_source.knowledge_key LIKE '%experiente%'
        THEN 'experiente'
      ELSE 'other'
    END AS qualifier_knowledge,
    CASE
      WHEN qualifier_source.urgency_key IS NULL
        OR qualifier_source.urgency_key = ''
        OR qualifier_source.urgency_key IN (
          'não informado',
          'nao informado',
          '(não informado)',
          '(nao informado)',
          'indefinido',
          'a definir',
          'a descobrir',
          'a confirmar',
          'tbd',
          'undefined',
          'unknown',
          'ambíguo',
          'ambiguo',
          'ambígua',
          'ambigua',
          'ainda não informado',
          'ainda nao informado',
          'não definido',
          'nao definido'
        )
        OR qualifier_source.urgency_key LIKE 'aguardando%'
        OR qualifier_source.urgency_key LIKE '%não informado%'
        OR qualifier_source.urgency_key LIKE '%nao informado%'
        THEN NULL
      WHEN qualifier_source.urgency_key LIKE '%futuro próximo%'
        OR qualifier_source.urgency_key LIKE '%futuro proximo%'
        OR qualifier_source.urgency_key LIKE '%futuro bem próximo%'
        OR qualifier_source.urgency_key LIKE '%futuro bem proximo%'
        OR qualifier_source.urgency_key LIKE '%futuro breve%'
        OR qualifier_source.urgency_key LIKE '%o quanto antes%'
        OR qualifier_source.urgency_key LIKE '%pressa%'
        THEN 'agora'
      WHEN qualifier_source.urgency_key = 'agora'
        OR (
          qualifier_source.urgency_key LIKE 'agora%'
          AND qualifier_source.urgency_key NOT LIKE '%futuro%'
        )
        THEN 'agora'
      WHEN qualifier_source.urgency_key = 'futuro'
        OR (
          qualifier_source.urgency_key LIKE 'futuro%'
          AND qualifier_source.urgency_key NOT LIKE '%agora%'
        )
        THEN 'futuro'
      ELSE 'other'
    END AS qualifier_urgency,
    qualifier_source.is_user_initiated
  FROM
    qualifier_source
),
simulation_before_handoff AS (
  SELECT
    population.id_deal,
    FROM_UTC_TIMESTAMP(
      consorcio_simulation.ts_created,
      'America/Sao_Paulo'
    ) AS ts_simulated,
    TRY_CAST(consorcio_simulation.credit_value AS DOUBLE) AS credit_value
  FROM
    datalake_consorcio.lead_scoring_population AS population
  INNER JOIN
    datalake_consorcio_clean.lead AS consorcio_lead
      ON consorcio_lead.uuid = population.uuid_lead
  INNER JOIN
    datalake_consorcio_clean.simulation AS consorcio_simulation
      ON consorcio_simulation.id_lead = consorcio_lead.id
  WHERE
    population.spec_version = {spec_version}
    AND population.ts_handoff IS NOT NULL
    AND consorcio_simulation.id_lead IS NOT NULL
    AND FROM_UTC_TIMESTAMP(
      consorcio_simulation.ts_created,
      'America/Sao_Paulo'
    ) < population.ts_handoff
),
simulation_ranked AS (
  SELECT
    simulation_before_handoff.id_deal,
    simulation_before_handoff.credit_value,
    simulation_before_handoff.ts_simulated,
    COUNT(*) OVER (
      PARTITION BY
        simulation_before_handoff.id_deal
    ) AS n_simulations_at_handoff,
    ROW_NUMBER() OVER (
      PARTITION BY
        simulation_before_handoff.id_deal
      ORDER BY
        simulation_before_handoff.ts_simulated DESC
    ) AS simulation_rank
  FROM
    simulation_before_handoff
),
simulation_at_handoff AS (
  SELECT
    simulation_ranked.id_deal,
    simulation_ranked.n_simulations_at_handoff,
    simulation_ranked.credit_value AS last_simulated_value,
    simulation_ranked.ts_simulated AS ts_last_simulated
  FROM
    simulation_ranked
  WHERE
    simulation_ranked.simulation_rank = 1
),
-- One row per pre-handoff bot/lead message. Keep both speakers so a bot
-- in the middle splits two human runs; drop attendant and hardcoded.
-- PlatConv role user is the lead (same as Blip human). Clocks are UTC
-- converted to America/Sao_Paulo, same as simulations vs ts_handoff.
chat_messages_in_window AS (
  SELECT
    qualifier_normalized.id_deal,
    'blip' AS chat_source,
    CASE
      WHEN LOWER(TRIM(blip_messages.role)) IN ('human', 'user') THEN 'human'
      ELSE 'ai'
    END AS speaker,
    FROM_UTC_TIMESTAMP(
      blip_messages.ts_created,
      'America/Sao_Paulo'
    ) AS ts_created,
    CAST(blip_messages.id_message AS STRING) AS id_message
  FROM
    qualifier_normalized
  INNER JOIN
    datalake_consorcio_clean.blip_messages AS blip_messages
      ON TRY_CAST(TRIM(blip_messages.id_crm) AS BIGINT) = qualifier_normalized.id_deal
  WHERE
    qualifier_normalized.ts_handoff IS NOT NULL
    AND LOWER(TRIM(blip_messages.role)) IN ('human', 'user', 'ai')
    AND FROM_UTC_TIMESTAMP(
      blip_messages.ts_created,
      'America/Sao_Paulo'
    ) < qualifier_normalized.ts_handoff
  UNION ALL
  SELECT
    qualifier_normalized.id_deal,
    'platconv' AS chat_source,
    CASE
      WHEN LOWER(TRIM(chat_messages.role)) IN ('human', 'user') THEN 'human'
      ELSE 'ai'
    END AS speaker,
    FROM_UTC_TIMESTAMP(
      chat_messages.ts_created,
      'America/Sao_Paulo'
    ) AS ts_created,
    CAST(chat_messages.id_message AS STRING) AS id_message
  FROM
    qualifier_normalized
  INNER JOIN
    datalake_consorcio.chat_messages AS chat_messages
      ON TRY_CAST(TRIM(chat_messages.id_crm) AS BIGINT) = qualifier_normalized.id_deal
  WHERE
    qualifier_normalized.ts_handoff IS NOT NULL
    AND LOWER(TRIM(chat_messages.role)) IN ('human', 'user', 'ai')
    AND FROM_UTC_TIMESTAMP(
      chat_messages.ts_created,
      'America/Sao_Paulo'
    ) < qualifier_normalized.ts_handoff
),
chat_turn_starts AS (
  SELECT
    chat_messages_in_window.id_deal,
    chat_messages_in_window.chat_source,
    chat_messages_in_window.speaker,
    chat_messages_in_window.ts_created,
    chat_messages_in_window.id_message,
    LAG(chat_messages_in_window.speaker) OVER (
      PARTITION BY
        chat_messages_in_window.id_deal,
        chat_messages_in_window.chat_source
      ORDER BY
        chat_messages_in_window.ts_created,
        chat_messages_in_window.id_message
    ) AS previous_speaker
  FROM
    chat_messages_in_window
),
chat_turns AS (
  SELECT
    chat_turn_starts.id_deal,
    chat_turn_starts.chat_source,
    chat_turn_starts.speaker,
    chat_turn_starts.ts_created,
    SUM(
      CASE
        WHEN chat_turn_starts.previous_speaker IS NULL
          OR chat_turn_starts.previous_speaker <> chat_turn_starts.speaker
        THEN 1
        ELSE 0
      END
    ) OVER (
      PARTITION BY
        chat_turn_starts.id_deal,
        chat_turn_starts.chat_source
      ORDER BY
        chat_turn_starts.ts_created,
        chat_turn_starts.id_message
      ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS turn_id
  FROM
    chat_turn_starts
),
chat_turn_bounds AS (
  SELECT
    chat_turns.id_deal,
    chat_turns.chat_source,
    chat_turns.turn_id,
    MAX(chat_turns.speaker) AS speaker,
    MIN(chat_turns.ts_created) AS ts_turn_start,
    MAX(chat_turns.ts_created) AS ts_turn_end
  FROM
    chat_turns
  GROUP BY
    chat_turns.id_deal,
    chat_turns.chat_source,
    chat_turns.turn_id
),
chat_turn_replies AS (
  SELECT
    chat_turn_bounds.id_deal,
    chat_turn_bounds.chat_source,
    chat_turn_bounds.speaker,
    LAG(chat_turn_bounds.speaker) OVER (
      PARTITION BY
        chat_turn_bounds.id_deal,
        chat_turn_bounds.chat_source
      ORDER BY
        chat_turn_bounds.turn_id
    ) AS previous_speaker,
    chat_turn_bounds.ts_turn_start,
    chat_turn_bounds.ts_turn_end,
    LAG(chat_turn_bounds.ts_turn_end) OVER (
      PARTITION BY
        chat_turn_bounds.id_deal,
        chat_turn_bounds.chat_source
      ORDER BY
        chat_turn_bounds.turn_id
    ) AS previous_ts_turn_end
  FROM
    chat_turn_bounds
),
n_lead_turns_by_source AS (
  SELECT
    chat_turn_replies.id_deal,
    chat_turn_replies.chat_source,
    SUM(
      CASE
        WHEN chat_turn_replies.speaker = 'human' THEN 1
        ELSE 0
      END
    ) AS n_lead_turns,
    CASE
      WHEN MAX(simulation_at_handoff.ts_last_simulated) IS NULL THEN NULL
      ELSE SUM(
        CASE
          WHEN chat_turn_replies.speaker = 'human'
            AND chat_turn_replies.ts_turn_end > simulation_at_handoff.ts_last_simulated
          THEN 1
          ELSE 0
        END
      )
    END AS n_lead_turns_post_simulation
  FROM
    chat_turn_replies
  LEFT JOIN
    simulation_at_handoff
      ON simulation_at_handoff.id_deal = chat_turn_replies.id_deal
  GROUP BY
    chat_turn_replies.id_deal,
    chat_turn_replies.chat_source
),
lead_reply_latencies AS (
  SELECT
    chat_turn_replies.id_deal,
    chat_turn_replies.chat_source,
    GREATEST(
      TIMESTAMPDIFF(
        SECOND,
        chat_turn_replies.previous_ts_turn_end,
        chat_turn_replies.ts_turn_start
      ),
      0
    ) AS reply_latency_sec
  FROM
    chat_turn_replies
  WHERE
    chat_turn_replies.speaker = 'human'
    AND chat_turn_replies.previous_speaker = 'ai'
),
seconds_bot_turn_to_lead_reply_by_source AS (
  SELECT
    lead_reply_latencies.id_deal,
    lead_reply_latencies.chat_source,
    PERCENTILE_APPROX(lead_reply_latencies.reply_latency_sec, 0.5) AS seconds_bot_turn_to_lead_reply
  FROM
    lead_reply_latencies
  GROUP BY
    lead_reply_latencies.id_deal,
    lead_reply_latencies.chat_source
),
chat_features_at_handoff AS (
  SELECT
    n_lead_turns_by_source.id_deal,
    MAX(
      CASE
        WHEN n_lead_turns_by_source.chat_source = 'blip'
        THEN n_lead_turns_by_source.n_lead_turns
      END
    ) AS n_lead_turns_blip,
    MAX(
      CASE
        WHEN n_lead_turns_by_source.chat_source = 'platconv'
        THEN n_lead_turns_by_source.n_lead_turns
      END
    ) AS n_lead_turns_platconv,
    MAX(
      CASE
        WHEN n_lead_turns_by_source.chat_source = 'blip'
        THEN n_lead_turns_by_source.n_lead_turns_post_simulation
      END
    ) AS n_lead_turns_post_simulation_blip,
    MAX(
      CASE
        WHEN n_lead_turns_by_source.chat_source = 'platconv'
        THEN n_lead_turns_by_source.n_lead_turns_post_simulation
      END
    ) AS n_lead_turns_post_simulation_platconv,
    MAX(
      CASE
        WHEN n_lead_turns_by_source.chat_source = 'blip'
        THEN seconds_bot_turn_to_lead_reply_by_source.seconds_bot_turn_to_lead_reply
      END
    ) AS seconds_bot_turn_to_lead_reply_blip,
    MAX(
      CASE
        WHEN n_lead_turns_by_source.chat_source = 'platconv'
        THEN seconds_bot_turn_to_lead_reply_by_source.seconds_bot_turn_to_lead_reply
      END
    ) AS seconds_bot_turn_to_lead_reply_platconv
  FROM
    n_lead_turns_by_source
  LEFT JOIN
    seconds_bot_turn_to_lead_reply_by_source
      ON seconds_bot_turn_to_lead_reply_by_source.id_deal = n_lead_turns_by_source.id_deal
      AND seconds_bot_turn_to_lead_reply_by_source.chat_source = n_lead_turns_by_source.chat_source
  GROUP BY
    n_lead_turns_by_source.id_deal
)
SELECT
  qualifier_normalized.id_deal,
  qualifier_normalized.qualifier_goal,
  qualifier_normalized.qualifier_investment_type,
  qualifier_normalized.qualifier_reason,
  qualifier_normalized.qualifier_knowledge,
  qualifier_normalized.qualifier_urgency,
  (
    CASE WHEN qualifier_normalized.qualifier_goal IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN qualifier_normalized.qualifier_investment_type IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN qualifier_normalized.qualifier_reason IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN qualifier_normalized.qualifier_knowledge IS NOT NULL THEN 1 ELSE 0 END
    + CASE WHEN qualifier_normalized.qualifier_urgency IS NOT NULL THEN 1 ELSE 0 END
  ) AS n_qualifiers_captured,
  CASE
    WHEN qualifier_normalized.ts_handoff IS NULL THEN NULL
    ELSE COALESCE(simulation_at_handoff.n_simulations_at_handoff, 0)
  END AS n_simulations_at_handoff,
  simulation_at_handoff.last_simulated_value,
  chat_features_at_handoff.n_lead_turns_blip,
  chat_features_at_handoff.n_lead_turns_platconv,
  COALESCE(
    chat_features_at_handoff.n_lead_turns_platconv,
    chat_features_at_handoff.n_lead_turns_blip
  ) AS n_lead_turns,
  chat_features_at_handoff.n_lead_turns_post_simulation_blip,
  chat_features_at_handoff.n_lead_turns_post_simulation_platconv,
  COALESCE(
    chat_features_at_handoff.n_lead_turns_post_simulation_platconv,
    chat_features_at_handoff.n_lead_turns_post_simulation_blip
  ) AS n_lead_turns_post_simulation,
  chat_features_at_handoff.seconds_bot_turn_to_lead_reply_blip,
  chat_features_at_handoff.seconds_bot_turn_to_lead_reply_platconv,
  CASE
    WHEN chat_features_at_handoff.n_lead_turns_platconv IS NOT NULL
    THEN chat_features_at_handoff.seconds_bot_turn_to_lead_reply_platconv
    ELSE chat_features_at_handoff.seconds_bot_turn_to_lead_reply_blip
  END AS seconds_bot_turn_to_lead_reply,
  qualifier_normalized.is_user_initiated,
  CURRENT_TIMESTAMP() AS ts_load,
  CAST({spec_version} AS INT) AS spec_version
FROM
  qualifier_normalized
LEFT JOIN
  simulation_at_handoff
    ON simulation_at_handoff.id_deal = qualifier_normalized.id_deal
LEFT JOIN
  chat_features_at_handoff
    ON chat_features_at_handoff.id_deal = qualifier_normalized.id_deal
