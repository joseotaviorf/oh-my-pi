drop table if exists quinto_messenger.dim_chat;
create table if not exists quinto_messenger.dim_chat (
    sk_chat varchar(100) primary key,
    channel varchar(25),
    customer_phone varchar(25),
    status varchar(25),
    is_forwarded boolean,
    ts_created timestamp,
    ts_updated timestamp
)
