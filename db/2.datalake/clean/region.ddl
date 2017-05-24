DROP TABLE IF EXISTS datalake_clean.region;
CREATE TABLE IF NOT EXISTS datalake_clean.region (
 id INT,
 criadaEm TIMESTAMP,
 atualizadoEm TIMESTAMP,
 nivel STRING,
 nome STRING,
 macroId INT,
 macroNome STRING,
 cidadeId INT,
 cidadeNome STRING,
 dt_timestamp TIMESTAMP
) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/region'
;