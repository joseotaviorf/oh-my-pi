drop table if exists quinto_messenger.fact_chats;
create table if not exists quinto_messenger.fact_chats (
    sk_chat varchar(100) primary key,
    sk_session varchar(100),
    sk_user bigint,
    sk_personal_document varchar(50),
    sk_created_date bigint,
    minutes_duration decimal(38,3),
    tasks integer
)
