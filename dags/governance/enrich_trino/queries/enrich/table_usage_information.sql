with explode_referenced_tables as (
  select
    queryId,
    explode(referencedTables) as referencedTable,
    year,
    month,
    day
  from
    data_platform_metrics.trino_query_log_events_metrics_clean_batch
  where
    year = {year}
    and month = {month}
    and day = {day}
), extrac_schema_and_table as (
  select
    queryId,
    regexp_extract(referencedTable, '"schema":"(\\w+)",') as database_name,
    split(regexp_extract(referencedTable, '"table":"(\\w+(\\$)*\\w+)",'), '[\$]') [0] as table_name,
    year,
    month,
    day
  from
    explode_referenced_tables
)
select
  database_name,
  table_name,
  count(*) as count_visualization,
  year,
  month,
  day
from
  extrac_schema_and_table
group by 
  database_name,
  table_name,
  year,
  month,
  day

