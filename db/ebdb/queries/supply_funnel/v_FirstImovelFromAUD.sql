create or replace view v_FirstImovelFromAUD as
select 
  id, min(REV) as REV
from
  Imovel_AUD   
group BY
  id