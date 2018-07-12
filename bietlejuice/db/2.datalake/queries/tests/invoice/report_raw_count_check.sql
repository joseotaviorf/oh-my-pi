-- because the API from Seu Barriga returns duplicate data, the following distinct must be applied
with _distinct as (
  select distinct *
  from datalake_raw.seubarriga_invoice
  where ym = '{year_month}'
)
select count(*)
from _distinct
;
