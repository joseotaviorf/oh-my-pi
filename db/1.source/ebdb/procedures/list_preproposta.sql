DROP PROCEDURE IF EXISTS ebdb.list_preproposta;
CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_preproposta()
BEGIN
select 
  p.id,
  p.aceitoAluguel,
  p.aceitoComprovarRenda,
  p.aceitoEncargos,
  p.aluguel,
  p.aluguelOriginal,
  p.condominioOriginal,
  -- p.iptuOriginal,
  p.dataAprovacao,
  p.edicao,
  p.status,
  p.proprietarioAceitouCondicoes5A,
  p.usuario_id,
  p.imovel_id,
  p.criadoEm,
  p.atualizadoEm,
  p.ultimoUpdateEdicao,
  pp_aud.dataPrimerioEnvio
from 
  PreProposta p
left join
(
 SELECT
	  pp.id,
	  min(FROM_UNIXTIME(ure.timestamp/1000)) as dataPrimerioEnvio
	FROM PreProposta pp
	JOIN PreProposta_AUD ppa ON ppa.id = pp.id AND ppa.edicao_MOD = true AND ppa.rEVTYPE = 1
	JOIN UsuarioRevisionEntity ure ON ure.id = ppa.REV
	LEFT JOIN PreProposta_AUD ppax 
		ON ppax.id = pp.id AND ppax.edicao_MOD = true AND ppax.rEVTYPE = 1 
		AND ppax.REV < ppa.REV -- this helps us to detect the first time it was changed
	WHERE
	  ppax.id IS null
	group by
		pp.id
) pp_aud
on pp_aud.id = p.id
;
END