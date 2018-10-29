DROP TABLE IF EXISTS skynet.listing2vec_embeddings

CREATE EXTERNAL TABLE skynet.listing2vec_embeddings (
  house_id integer,
  frequency double,
  occurrence integer,
  embeddings array<double>
) PARTITIONED BY (dt date)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-skynet/listing2vec/embeddings/'

MSCK REPAIR TABLE skynet.listing2vec_embeddings
