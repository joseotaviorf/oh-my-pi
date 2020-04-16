drop table if exists zendesk.fact_chats;
create table if not exists zendesk.fact_chats (
    sk_chat varchar(30),
    sk_ticket bigint,
    sk_chat_started_date int,
    sk_chat_started_date_local int,
    number_of_engagements smallint,
    number_of_unique_departments smallint,
    number_of_unique_agents smallint,
    first_engagement_department varchar(200),
    last_chat_department varchar(200),
    seconds_chat_duration bigint,
    seconds_first_reply_time float,
    seconds_average_reply_time float,
    seconds_max_reply_time float,
    ts_load timestamp
)