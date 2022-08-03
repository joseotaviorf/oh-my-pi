drop table if exists money_laundering_prevention.dim_suspicion;
create table if not exists money_laundering_prevention.dim_suspicion (
    sk_suspicion INT,
    name VARCHAR,
    ts_load TIMESTAMP
);
ALTER TABLE money_laundering_prevention.dim_suspicion OWNER TO databricks;
