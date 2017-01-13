create view v_ImovelStatusChangedDateDetails as
select 
  cur.*,
  pre.status_time as previous_status_time,
  pub.status_time as published_status_time
from 
  v_ImovelStatusChangedDate cur
left join
  v_ImovelStatusChangedDate pre
  on pre.id = cur.id
  and pre.REV = (SELECT max(REV) from v_ImovelStatusChangedDate aux where aux.id = cur.id and aux.REV < cur.REV)
left join
  v_ImovelStatusChangedDate pub
  on pub.id = cur.id
  and pub.REV = (SELECT max(REV) from v_ImovelStatusChangedDate aux where aux.id = cur.id and aux.REV <= cur.REV and aux.actual_status = 'publicado')
