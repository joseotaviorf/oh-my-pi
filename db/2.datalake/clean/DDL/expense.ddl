DROP TABLE IF EXISTS datalake_clean.expense;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.expense (
 id BIGINT,
 dataConsolidado DATE,
 dataDespesa DATE,
 pagante STRING,
 responsavel STRING,
 tipo STRING,
 valor DECIMAL(14,4),
 cobranca_id BIGINT,
 descricao STRING,
 automatica SMALLINT,
 atualizadoEm TIMESTAMP,
 criadoEm TIMESTAMP
  ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/expense'
;