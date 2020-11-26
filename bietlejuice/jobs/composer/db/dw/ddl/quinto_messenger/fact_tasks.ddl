drop table if exists quinto_messenger.fact_tasks;
create table if not exists quinto_messenger.fact_tasks (
    sk_task varchar(100) primary key,
    sk_chat varchar(100),
    sk_quinto_messenger_agent bigint,
    sk_created_date bigint,
    is_forwarded boolean,
    seconds_first_reply decimal(38,3),
    task_number integer
)
