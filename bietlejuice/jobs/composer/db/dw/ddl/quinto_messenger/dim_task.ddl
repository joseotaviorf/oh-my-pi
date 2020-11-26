drop table if exists quinto_messenger.dim_task;
create table if not exists quinto_messenger.dim_task (
    sk_task varchar(100) primary key,
    channel varchar(25),
    department varchar(50),
    status varchar(25),
    completion_reason varchar(50),
    customer_type varchar(50),
    contact_motivation varchar(50),
    contact_theme varchar(50),
    ts_created timestamp,
    ts_updated timestamp
)
