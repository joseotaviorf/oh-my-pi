drop table if exists agent.agent_contract;

create table if not exists agent.agent_contract (
agent_id integer,
"timestamp" timestamp,
workcontract_id integer
)
;