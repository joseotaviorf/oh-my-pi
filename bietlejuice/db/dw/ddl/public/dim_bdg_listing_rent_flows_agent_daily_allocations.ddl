DROP TABLE IF EXISTS agent.dim_bdg_listing_rent_flows_agent_daily_allocations;
CREATE TABLE IF NOT EXISTS agent.dim_bdg_listing_rent_flows_agent_daily_allocations
( 
  sk_listing_rent_flow BIGINT,
  sk_date INTEGER,
  sk_agent INTEGER,
  sk_slot_date_agent BIGINT,
  ts_load TIMESTAMP DEFAULT GETDATE()
)
;

ALTER TABLE agent.dim_bdg_listing_rent_flows_agent_daily_allocations OWNER TO databricks;

CALL grant_all_permissions_on_schema('agent');
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA agent TO GROUP etl;
GRANT ALL ON SCHEMA agent TO GROUP ETL;
