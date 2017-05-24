DROP TABLE IF EXISTS datalake_clean.pre_proposal;
CREATE TABLE IF NOT EXISTS datalake_clean.pre_proposal (
 id INT,
 aceitoAluguel INT,
 aceitoComprovarRenda INT,
 aceitoEncargos INT,
 aluguel INT,
 aluguelOriginal INT,
 condominioOriginal INT,
 dataAprovacao INT,
 edicao STRING,
 status STRING,
 proprietarioAceitouCondicoes5A INT,
 usuario_id BIGINT,
 imovel_id BIGINT,
 criadoEm TIMESTAMP,
 atualizadoEm TIMESTAMP,
 ultimoUpdateEdicao INT
) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/pre_proposal'
;