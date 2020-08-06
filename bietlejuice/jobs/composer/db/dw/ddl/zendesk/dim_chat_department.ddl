drop table if exists zendesk.dim_chat_department;
create table if not exists zendesk.dim_chat_department (
    sk_chat_department bigint,
    name varchar(255),
    description varchar(500),
    is_enabled boolean,
    members varchar(2000),
    ts_load timestamp    
)