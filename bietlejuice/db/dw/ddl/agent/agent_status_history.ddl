drop table if exists agent.agent_status_history;

create table if not exists agent.agent_status_history (
agent_id integer,
status varchar(25),
start_date date,
end_date date
)
;