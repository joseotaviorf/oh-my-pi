CREATE SCHEMA IF NOT EXISTS keys_tracking;

DROP TABLE IF EXISTS keys_tracking.dim_agents_with_keys;
CREATE TABLE keys_tracking.dim_agents_with_keys (
    sk_house_listing BIGINT,
    sk_agent BIGINT,
    sk_house BIGINT,
    all_id_agents VARCHAR(1024), 
    has_keys_with_agent_attributed BOOLEAN,
    has_keys_with_agent_delivered BOOLEAN,
    has_keys_with_agent_returned BOOLEAN,
    is_delivered_on_another_listing BOOLEAN,
    is_keys_with_agent_eligible BOOLEAN,
    is_keys_with_agent_opt_in BOOLEAN,
    dt_attributed DATE,
    dt_delivered DATE,
    dt_optin DATE,
    dt_publicated DATE,
    dt_returned DATE,
    ts_load TIMESTAMP
);
ALTER TABLE keys_tracking.dim_agents_with_keys OWNER TO airflow;

CALL grant_all_permissions_on_schema('keys_tracking');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA keys_tracking TO GROUP etl;
GRANT ALL ON SCHEMA keys_tracking TO GROUP ETL;