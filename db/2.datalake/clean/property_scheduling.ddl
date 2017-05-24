DROP TABLE IF EXISTS datalake_clean.property_scheduling;
CREATE EXTERNAL TABLE IF NOT EXISTS datalake_clean.property_scheduling (
 id_property_scheduling BIGINT,
 id_imovel INT,
 id_scheduling INT,
 id_owner INT,
 id_user_affiliate INT,
 id_user_agent INT,
 id_user_visitor INT,
 id_user_visit_agent INT,
 id_visit INT,
 visit_created_from_app INT,
 visit_created_type STRING,
 visit_last_updated_from_app INT,
 visit_last_updated_type STRING,
 id_rental_flow INT,
 id_negotiation INT,
 dt_negotiation TIMESTAMP,
 id_pre_proposal INT,
 id_proposal INT,
 id_contract INT,
 dt_contract_anullment DATE
) ROW FORMAT DELIMITED
    FIELDS TERMINATED BY ','
    LINES TERMINATED BY '\n'
LOCATION 's3://5a-datalake/clean/property_scheduling'
;