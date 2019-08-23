select
    v.*,
    now()
from v_ImovelStatusHistory v
join Imovel_AUD i
    on i.id = v.id
join UsuarioRevisionEntity ure
    on ure.id = i.REV
    where cast(from_unixtime(ure.timestamp/1000) as date) >= '{}'
      and cast(from_unixtime(ure.timestamp/1000) as date) < '{}'