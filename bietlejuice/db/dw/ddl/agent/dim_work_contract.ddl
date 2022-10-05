DROP TABLE IF EXISTS agent.dim_work_contract;
CREATE TABLE agent.dim_work_contract (
    sk_work_contract BIGINT PRIMARY KEY,
    id_work_contract BIGINT,
    contract_name VARCHAR(256),
    rede_partner VARCHAR(256),
    is_active BOOLEAN,
    is_rede_contract BOOLEAN,
    is_for_sale_contract BOOLEAN,
    is_for_rent_contract BOOLEAN,
    ts_created TIMESTAMP,
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE agent.dim_work_contract OWNER TO databricks;