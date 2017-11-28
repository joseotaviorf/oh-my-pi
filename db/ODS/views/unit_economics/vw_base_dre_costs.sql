drop view if exists vw_base_dre_costs;
create or replace view vw_base_dre_costs as
select
  "Value" as dre_value,
  "Month"::date as dre_date,
  "Category" as dre_category
from files.costs_dre
where "Value" != 0
;