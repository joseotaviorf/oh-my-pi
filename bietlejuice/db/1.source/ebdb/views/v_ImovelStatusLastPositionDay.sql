CREATE or replace view v_ImovelStatusLastPositionDay
as
select 
  a.id,
  a.status_date, 
  max(a.rev) as REV,
  max(a.status_time) as status_changed
from
  v_ImovelStatusChangedDate a
-- WHERE  a.id = 892763278
group by
  a.id,
  a.status_date