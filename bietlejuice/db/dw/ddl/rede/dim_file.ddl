DROP TABLE IF EXISTS rede.dim_file;
CREATE TABLE rede.dim_file (
    sk_file BIGINT PRIMARY KEY,
    id_file BIGINT,
    hash VARCHAR,
    file_name VARCHAR,
    type VARCHAR,
    url VARCHAR,
    ts_created TIMESTAMP,
    ts_updated TIMESTAMP,
    ts_load TIMESTAMP
);
ALTER TABLE rede.dim_file OWNER TO airflow;