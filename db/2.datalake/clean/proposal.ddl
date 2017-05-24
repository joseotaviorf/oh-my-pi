DROP TABLE IF EXISTS datalake_clean.proposal;
CREATE TABLE IF NOT EXISTS datalake_clean.proposal (
 id INT,
 dataParaMudanca TIMESTAMP,
 dataProposta TIMESTAMP,
 garantia STRING,
 motivacao STRING,
 propostaAluguel DOUBLE PRECISION,
 status STRING,
 ticketID INT,
 dataAprovacao TIMESTAMP,
 inquilinoEnviouDocumentos INT,
 dataDocumentosEnviados TIMESTAMP,
 proprietarioEnviouDocumentos INT,
 dataDocumentosProprietarioEnviados TIMESTAMP,
 inquilinoAceitouContrato INT,
 proprietarioAceitouContrato INT,
 statusDocumentacaoInq STRING,
 statusDocumentacaoProp STRING,
 fazerTermoAditivo INT,
 preProposta_id INT,
 criadoEm TIMESTAMP,
 atualizadoEm TIMESTAMP
) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/proposal'
;