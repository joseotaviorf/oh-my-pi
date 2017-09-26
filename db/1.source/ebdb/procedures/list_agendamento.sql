DROP PROCEDURE IF EXISTS ebdb.list_agendamento;

CREATE DEFINER = 'QuintoAndarMain'@'%'
PROCEDURE ebdb.list_agendamento()
BEGIN
select 
  a.id,
  a.data,
  a.status,
  a.tipo,
  a.hash,
  a.confirmado,
  a.encerrado,
  a.agenteFixo,
  a.fupVisita,
  a.dataFupVisita,
  a.reagendadoDe_id,
  a.visitante_id,
  a.visita_id,
  a.imovel_id,
  a.agente_id,
  a.atendente_id,
  a.fluxoLocacao_id,
  a.criadoEm,
  a.atualizadoEm,
  a.slotDia,
  m.motivo as reason,
  ap.name as reason_category,
  vo.nome as last_update_source,
  case 
  	when cast(FROM_UNIXTIME(rcanc.`timestamp`/1000) as date) > a.data then null 
  	else FROM_UNIXTIME(rcanc.`timestamp`/1000)
  end as cancel_timestamp,
  vo2.nome as first_update_source
from 
  Agendamento a
-- MUDANCA STATUS
left join
	(
		select
			m.agendamento_id,
			m.status,
			max(id) as id
		from
			MudancaStatusAgendamento m
		group by
			m.agendamento_id,
			m.status
	) ms
	on a.id = ms.agendamento_id
	and a.status = ms.status
left join
	MudancaStatusAgendamento m
	on m.id = ms.id
left join
	AppointmentChangeReasonCategory ap
	on ap.id = m.reasonCategory_id
left join 
	VisitaOrigem vo 
	on vo.id = a.origemUltimaAtualizacao_id
-- DATA DE CANCELAMENTO
left join
	(
		select
			id,
			min(REV) as REV_Cancelado
		from
			Agendamento_AUD
		where
			status='Cancelado'
			and status_MOD = 1
		group by
			id
	) c
	on c.id = a.id
left join
	UsuarioRevisionEntity rcanc
	on rcanc.id = c.REV_Cancelado
left join
    ( select id, min(REV) as min_rev from Agendamento_AUD group by id ) au1
    on a.id = au1.id
left join
	Agendamento_AUD au2
    on au1.id = au2.id and au1.min_rev = au2.REV
left join
    VisitaOrigem vo2
    on au2.origemUltimaAtualizacao_id = vo2.id
;
END