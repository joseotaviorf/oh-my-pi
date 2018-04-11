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
  p.dataAprovacao,
  p.edicao,
  p.status,
  p.proprietarioAceitouCondicoes5A,
  p.usuario_id,
  p.imovel_id,
  p.criadoEm,
  p.atualizadoEm,
  p.ultimoUpdateEdicao,
  pp_aud.dataPrimerioEnvio,
  p.code,
  p.rejectionReason as rejection_reason,
  (ani.descricao is null) as animais_condition,
  (mudar.descricao is null) as quando_vai_mudar_condition,
  (morar.descricao is null) as quem_vai_morar_condition,
  coalesce(special_conditions.special_conditions_count,0) as special_conditions_count,
  coalesce(special_conditions.remove_conditions,0) as remove_conditions,
  coalesce(special_conditions.include_conditions,0) as include_conditions,
  coalesce(special_conditions.maintenance_or_repair_conditions,0) as maintenance_or_repair_conditions,
  coalesce(special_conditions.replace_or_modify_conditions,0) as replace_or_modify_conditions,
  coalesce(special_conditions.other_conditions,0) as other_conditions
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
left join
    CondicaoProposta ani
    on ani.id = p.animais_id
left join
    CondicaoProposta mudar
    on mudar.id = p.quandoVaiMudar_id
left join
    CondicaoProposta morar
    on morar.id = p.quemVaiMorar_id
left join
(
	select
		pp.id,
		count(cp.id) as special_conditions_count,
		sum(cp.titulo = 'Remove') as remove_conditions,
		sum(cp.titulo = 'Include') as include_conditions,
		sum(cp.titulo = 'MaintenanceOrRepair') as maintenance_or_repair_conditions,
		sum(cp.titulo = 'ReplaceOrModify') as replace_or_modify_conditions,
		sum(cp.titulo not in ('Remove','Include','MaintenanceOrRepair','ReplaceOrModify')) as other_conditions
	from
		PreProposta pp
	left join
		PreProposta_CondicaoProposta pcp
		on pp.id = pcp.PreProposta_id
	left join
		CondicaoProposta cp
		on cp.id = pcp.condicoes_id
	where cp.id is not null
	group by pp.id
) special_conditions
on p.id = special_conditions.id
;
END