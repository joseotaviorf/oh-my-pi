DROP TABLE IF EXISTS agent.dim_agent_contract_type;

CREATE TABLE IF NOT EXISTS agent.dim_agent_contract_type (
    sk_agent_contract_type integer,
    slots_per_saturday integer,
    slots_per_weekday integer,
    contract_name varchar(100),
    contract_type varchar(100)
) ;