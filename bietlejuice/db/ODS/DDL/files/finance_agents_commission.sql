drop table if exists files.finance_agents_commission;
create table files.finance_agents_commission (
    agent_id int not null,
    agent_name varchar(200) not null,
    dt date not null,
    percentage decimal(5,2),
    value double precision
);