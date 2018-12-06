select
    *,
    now()
from v_ImovelStatusHistory
where id in (
    select distinct id
    from v_Imovel_AUD  a
    where a.date_status_changed >= '{}'
      and a.date_status_changed < '{}'
)
;