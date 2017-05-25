DROP TABLE IF EXISTS datalake_clean.charging;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.charging (
 id BIGINT,
 dataInquilinoPagou TIMESTAMP,
 dataPagarProprietario DATE,
 dataProprietarioFoiPago TIMESTAMP,
 fimPeriodo DATE,
 inicioPeriodo DATE,
 inquilinoPagou SMALLINT,
 proprietarioFoiPago SMALLINT,
 status STRING,
 vencimentoBoleto DATE,
 contrato_id BIGINT,
 valorTotalInquilino DECIMAL(14,4),
 valorTotalProprietario DECIMAL(14,4),
 dataFechamento DATE,
 boletoClone STRING,
 criadoEm TIMESTAMP,
 valorRecebido DECIMAL(14,4),
 gerarNF SMALLINT,
 atualizadoEm TIMESTAMP,
 regerarDespesas SMALLINT,
 dataAutoEnvioDemonstrativoProp TIMESTAMP,
 linhaDigitavel STRING,
 dataEnvioSmsLembrete TIMESTAMP
  ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/charging'
;