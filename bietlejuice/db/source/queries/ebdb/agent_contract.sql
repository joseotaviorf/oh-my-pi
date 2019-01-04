select
	aud.id,
	from_unixtime(ure.TIMESTAMP/1000) as timestamp,
	workContract_id
from DadosAgente_AUD aud
join UsuarioRevisionEntity ure on aud.REV = ure.id
order by 1, 2