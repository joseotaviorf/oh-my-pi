DROP TABLE IF EXISTS datalake_clean.booking;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.booking (
 id INT,
 data DATE,
 status STRING,
 tipo STRING,
 hash STRING,
 confirmado STRING,
 encerrado STRING,
 agenteFixo STRING,
 fupVisita STRING,
 dataFupVisita TIMESTAMP,
 reagendadoDe_id INT,
 visitante_id BIGINT,
 visita_id BIGINT,
 imovel_id BIGINT,
 agente_id BIGINT,
 atendente_id BIGINT,
 fluxoLocacao_id BIGINT,
 criadoEm TIMESTAMP,
 atualizadoEm TIMESTAMP,
 slotDia INT
   ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/booking'
;