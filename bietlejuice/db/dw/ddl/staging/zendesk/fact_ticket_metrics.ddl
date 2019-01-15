drop table if exists staging.zendesk_fact_ticket_metrics;

create table if not exists staging.zendesk_fact_ticket_metrics(
    sk_ticket integer,
    sk_house_listing bigint,
    sk_contract integer,
    sk_client integer,
    sk_owner integer,
    sk_requester bigint,
    sk_submitter bigint,
    sk_assingee bigint,
    sk_created_date integer,
    sk_solved_date integer,
    sk_extraction_date integer,
    sk_chat_started_date integer,
    sk_chat_started_time varchar,
    minutes_first_reply_time varchar,
    minutes_first_resolution_time varchar,
    minutes_requester_wait_time varchar,
    minutes_agent_wait_time varchar,
    minutes_on_hold_time varchar,
    minutes_full_resolution_time varchar,
    reopens varchar,
    replies varchar,
    has_public_comments varchar,
    status varchar,
    ts_load varchar
);