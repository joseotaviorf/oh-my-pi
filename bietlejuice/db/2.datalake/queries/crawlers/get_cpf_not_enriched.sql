with crawled_cpfs as (
  select
    regexp_extract_all(owners, 'CPF (\d{3}\.\d{3}\.\d{3}-\d{2})', 1) as cpfs
  from datalake_raw.crawled_cpf
)
select
  distinct t.cpf
from crawled_cpfs
cross join unnest(cpfs) as t(cpf)