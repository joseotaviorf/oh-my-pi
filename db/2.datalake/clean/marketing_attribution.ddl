DROP TABLE IF EXISTS datalake_clean.marketing_attribution;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.marketing_attribution (
 id BIGINT,
 uuid STRING,
 tipo STRING,
 imovel_id BIGINT,
 usuario_id BIGINT,
 campaign STRING,
 channel STRING,
 event_type STRING,
 mobile_app STRING,
 platform STRING,
 subchannel STRING,
 adquirido_em TIMESTAMP,
 criado_em TIMESTAMP,
 atualizado_em TIMESTAMP
 ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/marketing_attribution'
;