with host_sessions as (
  select
    id_langfuse_session as id_session,
    id_user,
    ts_created as session_started_at,
    host_tag as host_name,
    is_escalated
  from
    datalake_chatbot.sessions
  where
    host_tag in ('ian', 'dominic', 'matias')
    and trim(lower(host_tag)) in ('ian', 'dominic', 'matias')
    and DATE(ts_created) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
  group by
    1,
    2,
    3,
    4,
    5
),
host_traces as (
  select
    t.id_trace,
    t.id_session,
    t.ts_created,
    t.input,
    t.output
  from
    datalake_langfuse_clean.traces as t
      inner join host_sessions as hs
        on t.id_session = hs.id_session
  where
    MAKE_DATE(t.year, t.month, t.day)
      BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
host_traces_parsed as (
  select
    id_trace,
    id_session,
    to_utc_timestamp(ts_created, 'America/Sao_Paulo') as input_text_ts_created,
    ARRAY_JOIN(
      TRANSFORM(
        FROM_JSON(input, 'STRUCT<messages: ARRAY<STRUCT<text: STRING>>>').messages,
        x -> TRIM(x.text)
      ),
      '\n'
    ) AS input_text,
    ARRAY_JOIN(
      TRANSFORM(
        FROM_JSON(
          output,
          'STRUCT<responses: ARRAY<STRUCT<response_type:STRING, content: STRUCT<full_text: STRING>>>>'
        ).responses,
        x -> IF(x.content.full_text IS NULL, x.response_type, TRIM(x.content.full_text))
      ),
      '\n'
    ) AS output_text,
    FROM_JSON(
      GET_JSON_OBJECT(input, '$.user_context.user_last_notifications'),
      'ARRAY<STRUCT<sent_at:STRING, template:STRING, text:STRING>>'
    ) as notification
  from
    host_traces
),
host_observations as (
  select
    o.id_observation,
    o.id_trace,
    o.ts_started,
    o.ts_ended,
    o.output,
    o.name,
    o.type,
    o.level,
    o.cost_details
  from
    datalake_langfuse_clean.observations as o
      inner join host_traces as hs
        on o.id_trace = hs.id_trace
  where
    MAKE_DATE(o.year, o.month, o.day)
      BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
conversation as (
  select
    traces.id_trace,
    traces.input_text_ts_created,
    traces.input_text,
    traces.output_text,
    max(to_utc_timestamp(observations.ts_ended, 'America/Sao_Paulo')) as output_text_ts_ended,
    TIMESTAMPDIFF(
      SECOND,
      min(to_utc_timestamp(observations.ts_started, 'America/Sao_Paulo')),
      max(to_utc_timestamp(observations.ts_ended, 'America/Sao_Paulo'))
    ) as latency,
    round(sum(observations.cost_details.total), 4) as total_cost
  from
    host_traces_parsed as traces
      left join host_observations as observations
        on traces.id_trace = observations.id_trace
  group by
    1,
    2,
    3,
    4
),
agents_and_tools as (
  select
    id_trace,
    array_join(
      COLLECT_SET(name)
        FILTER (

          WHERE type = 'AGENT'
          AND NOT REGEXP_LIKE(name, '(?i)input|reactplanner|^clear_')

        ),
      ', '
    ) AS agents,
    array_join(
      COLLECT_SET(name)
        FILTER ( WHERE type = 'TOOL' ),
      ', '
    ) AS tools,
    array_join(
      COLLECT_SET(name)
        FILTER (

          WHERE type = 'TOOL'
          AND level = 'ERROR'

        ),
      ', '
    ) AS tools_with_error
  from
    host_observations
  where
    type IN ('TOOL', 'AGENT')
  group by
    1
),
generation as (
  select
    'GENERATION' AS type,
    id_trace,
    id_observation,
    ts_started,
    coalesce(
      ARRAY_JOIN(
        TRANSFORM(
          FROM_JSON(output, 'STRUCT<tool_calls: ARRAY<STRUCT<name:STRING>>>').tool_calls,
          x -> x.name
        ),
        '\n'
      ),
      IF(GET_JSON_OBJECT(output, '$.content.moderated') IS NOT NULL, 'moderated', NULL),
      IF(GET_JSON_OBJECT(output, '$.content.complete_answer') IS NOT NULL, 'complete_answer', NULL)
    ) AS name,
    coalesce(
      ARRAY_JOIN(
        TRANSFORM(
          FROM_JSON(
            output,
            'STRUCT<tool_calls: ARRAY<STRUCT<args: STRUCT<instructions: STRING, query: STRING, answer_to_supervisor: STRING, message_to_user: STRING>>>>'
          ).tool_calls,
          x ->
            COALESCE(
              concat(
                '<span style="color:#8b93a1;font-size:11px;font-weight:600">',
                'instructions: ',
                '</span>',
                '<br>',
                x.args.instructions
              ),
              concat(
                '<span style="color:#8b93a1;font-size:11px;font-weight:600">',
                'query: ',
                '</span>',
                '<br>',
                x.args.query
              ),
              concat(
                '<span style="color:#8b93a1;font-size:11px;font-weight:600">',
                'answer_to_supervisor: ',
                '</span>',
                '<br>',
                x.args.answer_to_supervisor
              ),
              concat(
                '<span style="color:#8b93a1;font-size:11px;font-weight:600">',
                'message_to_user: ',
                '</span>',
                '<br>',
                x.args.message_to_user
              )
            )
        ),
        '\n'
      ),
      GET_JSON_OBJECT(output, '$.content.moderated'),
      GET_JSON_OBJECT(output, '$.content.complete_answer')
    ) AS arguments,
    round(cost_details.total, 4) as llm_cost
  from
    host_observations
  where
    type = 'GENERATION'
),
kb_extraction as (
  select
    id_trace,
    id_observation,
    ts_started,
    explode(
      TRANSFORM(
        FROM_JSON(output, 'STRUCT<articles: ARRAY<STRUCT<content_id:STRING>>>').articles,
        x -> x.content_id
      )
    ) as content_id,
    coalesce(round(cost_details.total, 4), 0) as llm_cost
  from
    host_observations
  where
    type = 'TOOL'
    and name = 'search_broker_documents_v2'
    and id_trace in (
      select
        id_trace
      from
        host_traces
    )
),
kb_usage as (
  select
    'KNOWLEDGE_BASE_USAGE' AS type,
    kb.id_trace,
    kb.id_observation,
    kb.ts_started,
    '📚 knowledge_base_content_used' as name,
    array_join(COLLECT_LIST(concat(kb.content_id, ' - ', bc.title, '<br>')), '\n') as arguments,
    coalesce(llm_cost, 0) as llm_cost
  from
    kb_extraction as kb
      left join datalake_knowledge_base_clean.bot_content as bc
        on kb.content_id = bc.id_content
  group by
    1,
    2,
    3,
    4,
    5,
    7
),
union_all as (
  select
    *
  from
    generation
  union all
  select
    *
  from
    kb_usage
),
ordering as (
  select
    *,
    row_number() over (partition by id_trace order by ts_started) as rn
  from
    union_all
),
formatted as (
  select
    id_trace,
    struct(
      rn,
      concat(
        '<div style="background:#181b21;border:1px solid #262b34;border-radius:8px;padding:8px 10px;margin:4px 0">',
        '<span style="color:#e8a33d;font-size:11px;font-weight:600">',
        name,
        '</span>',
        '<span style="color:#5b6270;font-size:10px;margin-left:8px">',
        'LLM Cost: ',
        llm_cost,
        ' USD',
        '</span>',
        '<div style="color:#c7cbd1;font-size:12px;margin-top:6px">',
        arguments,
        '</div>',
        '</div>'
      ) as html
    ) as item
  from
    ordering
),
trace_blocks as (
  select
    st.id_trace,
    st.id_session,
    st.ts_created,
    concat(
      '<div style="margin-bottom:20px">',
      '<div style="display:flex;justify-content:flex-end;margin-bottom:8px">',
      '<div style="background:#2f7a57;color:#fff;border-radius:12px 12px 2px 12px;padding:10px 14px;max-width:70%;font-size:14px">',
      any_value(conversation.input_text),
      '<div style="text-align:right;color:rgba(255,255,255,0.7);font-size:10px;margin-top:4px">',
      any_value(date_format(conversation.input_text_ts_created, 'HH:mm')),
      '</div></div></div>',
      '<div style="display:flex;justify-content:flex-start">',
      '<div style="background:#1c2028;border:1px solid #2a2f3a;color:#e6e8eb;border-radius:12px 12px 12px 2px;padding:10px 14px;max-width:75%;font-size:14px">',
      '<div style="color:#3ecf8e;font-weight:700;font-size:12px;margin-bottom:4px">',
      'Matias',
      '</div>',
      any_value(conversation.output_text),
      '<div style="text-align:right;color:#5b6270;font-size:10px;margin-top:6px">',
      any_value(date_format(conversation.output_text_ts_ended, 'HH:mm')),
      ' · ',
      any_value(conversation.latency),
      's · ',
      any_value(conversation.total_cost),
      ' USD',
      '</div></div></div>',
      '<div style="color:#5b6270;font-size:11px;margin:6px 0 0 4px">',
      '🤖 ',
      any_value(coalesce(aat.agents, '')),
      '&nbsp;&nbsp;',
      '🔧 ',
      any_value(coalesce(aat.tools, '')),
      '&nbsp;&nbsp;',
      '❌ ',
      any_value(coalesce(aat.tools_with_error, '')),
      '</div>',
      '</div>'
    ) as trace_html_simple,
    concat(
      '<div style="margin-bottom:20px">',
      '<div style="display:flex;justify-content:flex-end;margin-bottom:8px">',
      '<div style="background:#2f7a57;color:#fff;border-radius:12px 12px 2px 12px;padding:10px 14px;max-width:70%;font-size:14px">',
      any_value(conversation.input_text),
      '<div style="text-align:right;color:rgba(255,255,255,0.7);font-size:10px;margin-top:4px">',
      any_value(date_format(conversation.input_text_ts_created, 'HH:mm')),
      '</div></div></div>',
      '<div style="display:flex;justify-content:flex-start">',
      '<div style="background:#1c2028;border:1px solid #2a2f3a;color:#e6e8eb;border-radius:12px 12px 12px 2px;padding:10px 14px;max-width:75%;font-size:14px">',
      '<div style="color:#3ecf8e;font-weight:700;font-size:12px;margin-bottom:4px">',
      'Matias',
      '</div>',
      any_value(conversation.output_text),
      '<div style="text-align:right;color:#5b6270;font-size:10px;margin-top:6px">',
      any_value(date_format(conversation.output_text_ts_ended, 'HH:mm')),
      ' · ',
      any_value(conversation.latency),
      's · ',
      any_value(conversation.total_cost),
      ' USD',
      '</div></div></div>',
      '<div style="color:#5b6270;font-size:11px;margin:6px 0 0 4px">',
      '🤖 ',
      any_value(coalesce(aat.agents, '')),
      '&nbsp;&nbsp;',
      '🔧 ',
      any_value(coalesce(aat.tools, '')),
      '&nbsp;&nbsp;',
      '❌ ',
      any_value(coalesce(aat.tools_with_error, '')),
      '</div>',
      '<div style="margin:8px 0 0 4px">',
      '<div style="color:#8b93a1;font-size:11px;font-weight:600;margin-bottom:4px">',
      'Observations',
      '</div>',
      array_join(transform(array_sort(collect_list(formatted.item)), x -> x.html), '\n'),
      '</div>',
      '</div>'
    ) as trace_html
  from
    host_traces st
      left join conversation
        on st.id_trace = conversation.id_trace
      left join formatted
        on st.id_trace = formatted.id_trace
      left join agents_and_tools aat
        on st.id_trace = aat.id_trace
  group by
    st.id_trace,
    st.id_session,
    st.ts_created
),
evals_scores as (
  select
    s.id_session,
    s.name,
    s.value,
    s.string_value,
    row_number() over (partition by s.id_session, s.name order by s.ts_created desc) as rn
  from
    datalake_langfuse_clean.scores as s
      inner join host_sessions as hs
        on s.id_session = hs.id_session
  where
    MAKE_DATE(s.year, s.month, s.day)
      BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
),
evals_formatted as (
  select
    id_session,
    case
      when lower(name) like '%frustration%' then 'Frustration'
      when lower(name) like '%naturalness%' then 'Naturalness'
      when lower(name) like '%friction%' then 'Friction'
      when lower(name) like '%resolution%' then 'Resolution'
      when
        lower(name) like '%laborlitigationrisk%'
        or (
          lower(name) like '%labor%'
          and lower(name) like '%litigation%'
        )
      then
        'Labor Litigation Risk'
      when
        lower(name) like '%airesistance%'
        or lower(name) like '%resistance%'
      then
        'AI Resistance'
      else
        initcap(
          regexp_replace(
            regexp_replace(
              regexp_replace(regexp_replace(lower(name), 'evaluator', ''), 'eval', ''),
              'matias',
              ''
            ),
            '^ian',
            ''
          )
        )
    end as clean_name,
    case
      when
        lower(name) like '%naturalness%'
      then
        case value
          when 2 then 'Natural'
          when 1 then 'Somewhat Robotic'
          when 0 then 'Robotic'
          else coalesce(string_value, cast(value as string))
        end
      else coalesce(string_value, cast(round(value, 2) as string))
    end as display_value
  from
    evals_scores
  where
    rn = 1
),
evals_cards as (
  select
    id_session,
    concat(
      '<div style="background:#1c2028;border:1px solid #2a2f3a;border-radius:10px;padding:14px 16px;min-width:150px;flex:1 1 45%">',
      '<div style="color:#8b93a1;font-size:12px;font-weight:600;margin-bottom:6px">',
      '📊 ',
      clean_name,
      '</div>',
      '<div style="color:#e8a33d;font-size:12px;font-weight:700">',
      display_value,
      '</div>',
      '</div>'
    ) as card_html
  from
    evals_formatted
),
evals_block as (
  select
    id_session,
    concat(
      '<div style="color:#8b93a1;font-size:12px;font-weight:700;letter-spacing:0.08em;margin:0 0 12px 4px">',
      '📊 AVALIAÇÕES AUTOMÁTICAS',
      '</div>',
      '<div style="display:flex;flex-wrap:wrap;gap:10px;margin-bottom:16px">',
      array_join(collect_list(card_html), ''),
      '</div>'
    ) as evals_html
  from
    evals_cards
  group by
    id_session
),
session_summary as (
  select
    st.id_session,
    min(st.ts_created) as session_date,
    count(distinct st.id_trace) as trace_count,
    sum(
      case
        when conversation.input_text is not null then 1
        else 0
      end
    )
      + sum(
        case
          when conversation.output_text is not null then 1
          else 0
        end
      ) as message_count,
    round(avg(conversation.latency), 1) as avg_latency
  from
    host_traces st
      left join conversation
        on st.id_trace = conversation.id_trace
  group by
    st.id_session
),
summary_block as (
  select
    id_session,
    concat(
      '<div style="display:flex;flex-wrap:wrap;gap:16px;align-items:center;color:#8b93a1;font-size:13px;padding:10px 0;',
      'border-top:1px solid #2a2f3a;border-bottom:1px solid #2a2f3a;margin-bottom:16px">',
      '<span>🗓 ',
      day(session_date),
      ' de ',
      case month(session_date)
        when 1 then 'janeiro'
        when 2 then 'fevereiro'
        when 3 then 'março'
        when 4 then 'abril'
        when 5 then 'maio'
        when 6 then 'junho'
        when 7 then 'julho'
        when 8 then 'agosto'
        when 9 then 'setembro'
        when 10 then 'outubro'
        when 11 then 'novembro'
        when 12 then 'dezembro'
      end,
      ' de ',
      year(session_date),
      '</span>',
      '<span>💬 ',
      message_count,
      ' mensagens</span>',
      '<span>⏱ latência média ',
      avg_latency,
      's</span>',
      '<span>🔎 ',
      trace_count,
      ' traces</span>',
      '<span style="color:#5b6270">ID: ',
      id_session,
      '</span>',
      '</div>'
    ) as summary_html
  from
    session_summary
),
date_pill as (
  select
    id_session,
    concat(
      '<div style="text-align:center;margin:16px 0">',
      '<span style="background:#232830;color:#8b93a1;font-size:12px;padding:4px 14px;border-radius:14px">',
      day(session_date),
      ' de ',
      case month(session_date)
        when 1 then 'janeiro'
        when 2 then 'fevereiro'
        when 3 then 'março'
        when 4 then 'abril'
        when 5 then 'maio'
        when 6 then 'junho'
        when 7 then 'julho'
        when 8 then 'agosto'
        when 9 then 'setembro'
        when 10 then 'outubro'
        when 11 then 'novembro'
        when 12 then 'dezembro'
      end,
      ' de ',
      year(session_date),
      '</span></div>'
    ) as date_pill_html
  from
    session_summary
),
notifications_exploded as (
  select
    id_session,
    msg.template as template_name,
    msg.text as content,
    msg.sent_at as ts_received
  from
    host_traces_parsed
    lateral view explode(notification) as msg
),
notifications_cards as (
  select
    id_session,
    ts_received,
    concat(
      '<div style="background:#1c2028;border:1px solid #d9822b;border-radius:8px;padding:10px 14px;margin:0 0 8px 0">',
      '<div style="color:#d9822b;font-weight:700;font-size:12px;margin-bottom:2px">',
      'Template: ',
      coalesce(template_name, 'Notificação'),
      '</div>',
      '<div style="color:#5b6270;font-size:10px;margin-bottom:6px">',
      coalesce(date_format(to_timestamp(ts_received), 'yyyy-MM-dd HH:mm:ss'), ''),
      '</div>',
      '<div style="color:#c7cbd1;font-size:13px">',
      content,
      '</div>',
      '</div>'
    ) as notif_html
  from
    notifications_exploded
),
notifications_block as (
  select
    id_session,
    concat(
      '<div style="color:#8b93a1;font-size:12px;font-weight:700;letter-spacing:0.08em;margin:0 0 12px 4px">',
      '🔔 NOTIFICAÇÕES RECEBIDAS',
      '</div>',
      array_join(
        transform(array_sort(collect_list(struct(ts_received, notif_html))), x -> x.notif_html),
        ''
      )
    ) as notifications_html
  from
    notifications_cards
  group by
    id_session
)
select
  any_value(trace_blocks.id_session) as id_session,
  any_value(host_sessions.id_user) as id_user,
  any_value(host_sessions.session_started_at) as session_started_at,
  any_value(host_sessions.host_name) as host_name,
  any_value(host_sessions.is_escalated) as is_escalated,
  concat(
    '<div style="background:#12151a;border-radius:14px;padding:20px;font-family:sans-serif">',
    coalesce(any_value(evals_block.evals_html), ''),
    coalesce(any_value(summary_block.summary_html), ''),
    coalesce(any_value(date_pill.date_pill_html), ''),
    coalesce(any_value(notifications_block.notifications_html), ''),
    array_join(
      transform(
        array_sort(collect_list(struct(trace_blocks.ts_created, trace_blocks.trace_html))),
        x -> x.trace_html
      ),
      '\n'
    ),
    '</div>'
  ) as conversation_with_traces_html,
  concat(
    '<div style="background:#12151a;border-radius:14px;padding:20px;font-family:sans-serif">',
    coalesce(any_value(summary_block.summary_html), ''),
    coalesce(any_value(date_pill.date_pill_html), ''),
    coalesce(any_value(notifications_block.notifications_html), ''),
    array_join(
      transform(
        array_sort(collect_list(struct(trace_blocks.ts_created, trace_blocks.trace_html_simple))),
        x -> x.trace_html_simple
      ),
      '\n'
    ),
    '</div>'
  ) as conversation_html,
  coalesce(any_value(evals_block.evals_html), '') as evals,
  year(any_value(host_sessions.session_started_at)) as year,
  month(any_value(host_sessions.session_started_at)) as month,
  day(any_value(host_sessions.session_started_at)) as day
from
  trace_blocks
    left join host_sessions
      on host_sessions.id_session = trace_blocks.id_session
    left join evals_block
      on evals_block.id_session = trace_blocks.id_session
    left join summary_block
      on summary_block.id_session = trace_blocks.id_session
    left join date_pill
      on date_pill.id_session = trace_blocks.id_session
    left join notifications_block
      on notifications_block.id_session = trace_blocks.id_session
group by
  trace_blocks.id_session
