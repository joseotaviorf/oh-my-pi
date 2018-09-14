create or replace view v_Imovel_AUD as
select 
  from_unixtime(rev.timestamp/1000) as status_changed, 
  cast(from_unixtime(rev.timestamp/1000) as date) as date_status_changed,
  rev.usuario_id,
  rev.motivo,
  i.*
from 
  Imovel_AUD i
inner JOIN
  UsuarioRevisionEntity rev 
  on rev.id = i.REV  