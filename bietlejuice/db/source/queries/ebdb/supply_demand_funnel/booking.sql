select
  a.id,
  a.data,
  a.status,
  a.tipo,
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
  replace(m.motivo, '\n', '') as reason,
  ap.name as reason_category,
  vo_update.nome as last_update_source,
  case
  	when cast(FROM_UNIXTIME(rcanc.`timestamp`/1000) as date) > a.data then null
  	else FROM_UNIXTIME(rcanc.`timestamp`/1000)
  end as cancel_timestamp,
  vo_create.nome as first_update_source,
  fup.inquilinoCompareceu as visitor_arrived,
  fup.motivoInquilino as visitor_missing_reason,
  fup.agenteCompareceu as agent_arrived,
  fup.motivoAgente as agent_missing_reason,
  fup.prorietarioCompareceu as owner_arrived,
  fup.motivoProprietario as owner_missing_reason,
  (case when e.successful=1 then 1 when e.successful=0 then 0 else null end) as successful_entrance,
  e.problem as troublesome_entrance,
  a.checkInStatus
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
left join Visita v
  on a.visita_id = v.id
left join VisitaOrigem vo_create
	on vo_create.id = v.origemCriacao_id
left join VisitaOrigem vo_update
	on vo_update.id = v.origemUltimaAtualizacao_id
left join
	(
		SELECT
			A.id as agendamento_id,
			(SELECT attended FROM ebdb.Visitor v where v.agendamento_id=A.id and type='Tenant' limit 1) as inquilinoCompareceu,
			(if((SELECT absenceReason FROM ebdb.Visitor v where v.agendamento_id=A.id and type='Agent' limit 1)='Absent', NULL,
			(SELECT absenceReason FROM ebdb.Visitor v where v.agendamento_id=A.id and type='Tenant' limit 1))) as motivoInquilino,
			(SELECT attended FROM ebdb.Visitor v where v.agendamento_id=A.id and type='Agent' limit 1) as agenteCompareceu,
			(SELECT absenceReason FROM ebdb.Visitor v where v.agendamento_id=A.id and type='Agent' limit 1) as motivoAgente,
			(SELECT attended FROM ebdb.Visitor v where v.agendamento_id=A.id and type='LandLord' limit 1) as prorietarioCompareceu,
			(SELECT absenceReason FROM ebdb.Visitor v where v.agendamento_id=A.id and type='LandLord' limit 1) as motivoProprietario,
			F.entrance_id idEntrance,
			F.comment as comentFup
		FROM ebdb.Agendamento A
		LEFT JOIN ebdb.Visita V on V.id = A.visita_id
		LEFT JOIN ebdb.Usuario UA on UA.id = V.agente_id
		LEFT JOIN ebdb.Usuario UV on UV.id = V.visitante_id
		LEFT JOIN ebdb.Visitor VI on VI.agendamento_id = A.id
		LEFT JOIN ebdb.FollowUpDetails F on A.followUpDetails_id = F.id
		GROUP BY VI.agendamento_id
		ORDER BY A.data, A.slotDia
	) fup
	on fup.agendamento_id = a.id
left join
	ebdb.Entrance e
	on fup.idEntrance = e.id
where DATE(coalesce(a.criadoEm, '1900-01-01 00:00:00')) <= DATE('{}')
