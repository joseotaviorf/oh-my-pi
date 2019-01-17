select
    count(1)
from
    ContaCorrente cc
join Usuario u on cc.usuario_id = u.id