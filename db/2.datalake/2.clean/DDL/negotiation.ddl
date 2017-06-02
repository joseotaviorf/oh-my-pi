DROP TABLE IF EXISTS datalake_clean.negotiation;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.negotiation (
 id INT,
 dataParaMudanca TIMESTAMP,
 deadlineEm TIMESTAMP,
 enviadaEm TIMESTAMP,
 garantia STRING,
 periodo STRING,
 propostaAluguel INT,
 respAluguel STRING,
 respAnimais STRING,
 respExplicacao STRING,
 respGarantias STRING,
 respInquilinos STRING,
 respItensEssenciais STRING,
 respItensPreferenciais STRING,
 respMudanca STRING,
 respPeriodo STRING,
 fase STRING,
 deAcordo_condominio INT,
 deAcordo_iptu INT,
 deAcordo_reserva INT,
 deAcordo_vencimento INT,
 fiador_cidade STRING,
 fiador_tipo STRING,
 fiador_vinculo STRING,
 status STRING,
 rejeicaoPendente INT,
 rejeitadaEm TIMESTAMP,
 motivoRejeicao STRING,
 criadoEm TIMESTAMP,
 atualizadoEm TIMESTAMP
 ) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/negotiation'
;