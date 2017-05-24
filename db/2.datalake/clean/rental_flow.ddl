DROP TABLE IF EXISTS datalake_clean.rental_flow;
CREATE TABLE IF NOT EXISTS datalake_clean.rental_flow (
  id BIGINT,
  atualizadoEm TIMESTAMP,
  criadoEm TIMESTAMP,
  cliente_id BIGINT,
  gerente_id BIGINT,
  imovel_id BIGINT,
  ignorarAntesDe TIMESTAMP,
  status STRING,
  etapaRejeitada SMALLINT,
  withoutIptu CHAR
) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/rental_flow'
;