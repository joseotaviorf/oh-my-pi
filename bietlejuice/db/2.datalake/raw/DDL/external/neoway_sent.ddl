drop table datalake_raw.neoway_sent

create external table datalake_raw.neoway_sent (
  cpf string
)
row format delimited
  lines terminated by '\n'
location 's3://5a-datalake/raw/external/owners/sent/'
;
