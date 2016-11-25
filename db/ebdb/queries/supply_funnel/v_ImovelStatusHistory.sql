create or replace view v_ImovelStatusHistory
as
select 
  case when a.status = 'publicado' 
    then from_unixtime(rev.timestamp/1000) 
    else coalesce (a.ultimaPublicacao, i.firstPublication) 
  end as datePublication,
  
  case when a.status = 'publicado' then 1 else 0 end as published,
  
  from_unixtime(rev.timestamp/1000) as dateStatusChanged,
  
  a.status as status_history,
  
  rev.usuario_id as userRevision,
  
  i.*,
  a.REV,
  a.status_MOD  
from 
  Imovel_AUD a
inner JOIN
  Imovel i
  on i.id = a.id  
inner JOIN
  UsuarioRevisionEntity rev 
  on rev.id = a.REV
left JOIN 
  v_FirstImovelFromAUD au
  on au.id = a.id
  and au.REV = a.REV
where 
  (a.status_MOD = 1  or (au.id is not null))
  -- and a.id = 892778796
;