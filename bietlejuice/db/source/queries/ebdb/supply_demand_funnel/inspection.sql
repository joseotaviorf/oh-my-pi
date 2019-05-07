select
	v.id,
	v.criadoEm as ts_created,
	v.dataVistoria as dt_inspected,
	v.imovel_id as id_house,
	v.vistoriador_id as id_user_inspector,
	v.status,
	v.comentario as "comment",
	v.contrato_id as id_contract,
	v.hash,
	v.aprovadoInquilino+0 as is_tenant_approved,
	v.aprovadoProprietario+0 as is_owner_approved,
	v.browserAprovacaoInquilino as browser_tenant_approval,
	v.browserAprovacaoProprietario as browser_owner_approval,
	v.comentarioInquilino as tenant_comment,
	v.comentarioProprietario as owner_comment,
	v.dataAprovacaoInquilino as ts_tenant_approved,
	v.dataAprovacaoProprietario as ts_owner_approved,
	v.ipAprovacaoInquilino as ip_tenant_approval,
	v.ipAprovacaoProprietario as ip_owner_approval,
	v.soAprovacaoInquilino as os_tenant_approval,
	v.soAprovacaoProprietario as os_owner_approval,
	v.atualizadoEm as ts_updated,
	v.expiraEm as ts_expired,
	v.ref_id as id_ref,
	v.tipo as "type",
	v.shortRevisarInq as short_review_tenant,
	v.shortRevisarProp as short_review_owner,
	v.finalReportPdfId as id_final_report_pdf,
	v.finalReportSentAt as dt_final_report_sent,
	v.itenCommented+0 as is_item_commented,
	v.finalReportCreated+0 as is_final_report_created,
	v.lastReportSent as last_report_sent,
	v.reportFinished+0 as is_report_finished,
	v.keyLocation as key_location,
	v.keyLocationDetails as key_location_details,
	v.inspectorGotAllInfo+0 as has_inspector_got_all_info,
	v.partialTenantReportSentAt as ts_partial_tenant_report_sent,
	v.partialOwnerReportSentAt as ts_partial_owner_report_sent,
	v.version,
	v.schedule_id as id_booking,
	v.scheduleObservations as schedule_observations,
	v.reportRevised as report_revised,
	v.scheduleDoubleChecked+0 as is_schedule_double_checked,
	comentario_vistoria.has_inspector_comment,
	comentario_vistoria.has_tenant_comment,
	comentario_vistoria.has_owner_comment
from Vistoria v
left join (
-- in order to avoid having to bring more than 3kk rows to memory, this subquery is being joined in the source
  select
    insp.id,
    count(ii_inspector.id) > 0 as has_inspector_comment,
    count(ii_tenant.id) > 0 as has_tenant_comment,
    count(ii_owner.id) > 0 as has_owner_comment
    from Vistoria insp
    left join ItemVistoria ii_inspector
      on insp.id = ii_inspector.vistoria_id
        and ii_inspector.comentario is not null
    left join ItemVistoria ii_tenant
      on insp.id = ii_tenant.vistoria_id
        and ii_tenant.comentarioInquilino is not null
    left join ItemVistoria ii_owner
      on insp.id = ii_owner.vistoria_id
        and ii_owner.comentarioProprietario is not null
    group by 1
    having count(ii_inspector.id) + count(ii_tenant.id) + count(ii_owner.id) > 0
) comentario_vistoria
	on v.id = comentario_vistoria.id
where date(coalesce(v.criadoEm, '1900-01-01 00:00:00')) <= date('{}')
;