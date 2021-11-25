DROP TABLE IF EXISTS janus.dim_rent_flow_taxonomy;

CREATE TABLE IF NOT EXISTS janus.dim_rent_flow_taxonomy
( 
    sk_rent_flow_taxonomy BIGINT PRIMARY KEY,
    id_rent_flow_taxonomy BIGINT,
    mkt_category VARCHAR(255),
    mkt_flow VARCHAR(255),
    mkt_completion VARCHAR(255),
    mkt_origin VARCHAR(255),
    mkt_channel VARCHAR(255),
    mkt_medium VARCHAR(255),
    mkt_source VARCHAR(255),
    mkt_platform VARCHAR(255),
    ts_load TIMESTAMP
)

ALTER TABLE janus.dim_rent_flow_taxonomy OWNER TO databricks;