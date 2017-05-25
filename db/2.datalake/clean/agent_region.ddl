DROP TABLE IF EXISTS datalake_clean.agent_region;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.agent_region (
 DadosAgente_id BIGINT,
 regioes_id BIGINT
    ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/agent_region'
;