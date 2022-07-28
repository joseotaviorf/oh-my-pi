drop table if exists zendesk.fact_chat_engagements;
create table if not exists zendesk.fact_chat_engagements (
    sk_chat_engagement varchar(30),
    sk_chat varchar(30),
    sk_engagement_department bigint,
    sk_zendesk_agent bigint,
    sk_engagement_started_date bigint,
    sk_engagement_started_date_local bigint,
    is_first_engagement_in_chat boolean,
    is_last_engagement_in_chat boolean,
    seconds_engagement_duration float,
    ts_load timestamp
)
