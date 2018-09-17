CREATE or replace view v_ImovelStatusChangedDate as
select 
  a.id,
  a.REV,
  a.status as actual_status,
  lpre.status as previous_status,
  a.status_changed as status_time,
  cast(a.status_changed as date) as status_date
from 
  v_Imovel_AUD a
left JOIN
  v_Imovel_AUD lpre
  on a.id = lpre.id
  and lpre.REV = (SELECT REV from Imovel_AUD aux where aux.id = a.id and aux.REV < a.REV  order by id, REV desc limit 1)
where 
  !(coalesce(a.status,'first') = coalesce(lpre.status,''))
  -- and a.id = 892769803-- 892763278 -- 892763344
