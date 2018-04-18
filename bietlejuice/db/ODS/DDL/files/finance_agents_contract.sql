drop table if exists files.finance_agents_contract;
create table files.finance_agents_contract (
    agent_id int,
    agent_name varchar(200),
    status varchar(50),
    property_id int,
    contract_id int,
    signature_date date,
    rent double precision
);