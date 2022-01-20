CREATE SCHEMA IF NOT EXISTS keys_tracking;

DROP TABLE IF EXISTS keys_tracking.dim_agents_with_keys;
CREATE TABLE keys_tracking.dim_agents_with_keys (
    sk_house_listing BIGINT,
    sk_agent BIGINT,
    sk_house BIGINT,
    all_id_agents VARCHAR(1024),
    days_attribution_to_first_vc INTEGER,
    days_attribution_to_first_vc_agent INTEGER,
    days_cs_to_return INTEGER,
    days_publication_to_attribution INTEGER,
    has_keys_with_agent_attributed BOOLEAN,
    has_keys_with_agent_delivered BOOLEAN,
    has_keys_with_agent_returned BOOLEAN,
    is_delivered_earlier_first_vc_agent BOOLEAN,
    is_delivered_first_vc BOOLEAN,
    is_delivered_first_vc_agent BOOLEAN,
    is_delivered_on_another_listing BOOLEAN,
    is_keys_with_agent_eligible BOOLEAN,
    is_keys_with_agent_opt_in BOOLEAN,
    is_fss BOOLEAN,
    ts_attributed TIMESTAMP,
    ts_contract_signed TIMESTAMP,
    ts_delivered TIMESTAMP,
    ts_first_vc TIMESTAMP,
    ts_first_vc_attributed TIMESTAMP,
    ts_optin TIMESTAMP,
    ts_publicated TIMESTAMP,
    ts_returned TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE keys_tracking.dim_agents_with_keys OWNER TO airflow;

CALL grant_all_permissions_on_schema('keys_tracking');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA keys_tracking TO GROUP etl;
GRANT ALL ON SCHEMA keys_tracking TO GROUP ETL;