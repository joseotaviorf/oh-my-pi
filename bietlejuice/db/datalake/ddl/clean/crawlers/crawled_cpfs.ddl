drop table datalake_clean.crawled_cpfs;
create external table datalake_clean.crawled_cpfs (
  cpf string,
  name string,
  abbreviation string,
  street_name string,
  street_number integer,
  phone_numbers string
)
partitioned by (
  dt date
)
stored as parquet
location 's3://5a-datalake/clean/crawled/cpfs'
;

msck repair table datalake_clean.crawled_cpfs;