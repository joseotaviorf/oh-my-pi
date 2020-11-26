drop table if exists quinto_messenger.dim_quinto_messenger_agent;
create table if not exists quinto_messenger.dim_quinto_messenger_agent (
    sk_quinto_messenger_agent bigint primary key,
    name varchar(100),
    email varchar(50),
    location varchar(25),
    skills varchar(200),
    ts_updated timestamp
)
