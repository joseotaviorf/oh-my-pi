drop table if exists teravoz.fact_call_agents_interactions;
create table if not exists teravoz.fact_call_agents_interactions (
    sk_call_agent_interaction bigint,
    sk_call varchar,
    sk_agent varchar,
    sk_call_queued bigint,
    sk_user bigint,
    sk_agent_answered_date bigint,
    sk_agent_answered_date_local bigint,
    email_agent varchar,
    extension_number int,
    seconds_call_ringing_time bigint,
    seconds_talk_time_agent bigint,
    is_call_answered_by_agent boolean,
    is_call_answered_from_outsourcing_company boolean,
    ts_agent_answered timestamp,
    ts_agent_answered_local timestamp,
    ts_agent_hangup timestamp,
    ts_agent_hangup_local timestamp,
    ts_agent_extension_rang timestamp,
    ts_agent_extension_rang_local timestamp,
    ts_load timestamp
)