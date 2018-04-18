drop table if exists datalake_raw.crm_tasks;
create external table datalake_raw.crm_tasks
(
  `_id` string,  
  `type` string,
  `dataInicio` timestamp,
  `realizadaEm` timestamp,
  `imovelId` int,
  `authorId` int,
  `authorName` string,
  `assigneeId` int,
  `assigneeName` string,
  `workgroupId` string,
  `workgroupTitle` string,
  `destinatarioId` int,
  `status` string,
  `descricao` string,
  `titulo` string
)
PARTITIONED BY (extracted_on date)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
LOCATION 's3://5a-datalake/raw/crm/tasks/';

MSCK REPAIR TABLE datalake_raw.crm_tasks;
