create or replace view v_ImovelStatusHistory
as

select 
  i.*,
  a.REV,
  case when a.status = 'publicado' 
    then l.status_time
    else l.published_status_time
  end as datePublication,
  
  case when a.status = 'publicado' then 1 else 0 end as published,
  
  l.status_time,
  l.status_date,  
  coalesce(l.actual_status, i.status) as status_history,
  i.status as current_status

from 
  v_Imovel_AUD a
inner JOIN
  Imovel i
  on i.id = a.id
inner JOIN
  v_ImovelStatusChangedDateDetails l
  on l.id = a.id
  and l.REV = a.REV

 -- where a.id =-- 892769803 -- 892778796

;