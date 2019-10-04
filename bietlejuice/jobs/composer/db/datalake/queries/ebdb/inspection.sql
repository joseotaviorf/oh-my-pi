WITH
    comments AS (
        SELECT
            vistoria_id,
            max(if(comentario is null, false, true)) AS has_inspector_comment,
            max(if(comentarioInquilino is null, false, true)) AS has_tenant_comment,
            max(if(comentarioProprietario is null, false, true)) AS has_owner_comment
        FROM
            datalake_ebdb_raw.itemvistoria
        GROUP BY
            vistoria_id
    )
SELECT
    vistoria.id AS id_inspection,
    vistoria.criadoEm AS ts_created,
    vistoria.dataVistoria AS dt_inspected,
    vistoria.imovel_id AS id_house,
    vistoria.vistoriador_id AS id_user_inspector,
    vistoria.status,
    vistoria.comentario AS comment,
    vistoria.contrato_id AS id_contract,
    vistoria.hash,
    vistoria.aprovadoInquilino AS is_tenant_approved,
    vistoria.aprovadoProprietario AS is_owner_approved,
    vistoria.browserAprovacaoInquilino AS browser_tenant_approval,
    vistoria.browserAprovacaoProprietario AS browser_owner_approval,
    vistoria.comentarioInquilino AS tenant_comment,
    vistoria.comentarioProprietario AS owner_comment,
    vistoria.dataAprovacaoInquilino AS ts_tenant_approved,
    vistoria.dataAprovacaoProprietario AS ts_owner_approved,
    vistoria.ipAprovacaoInquilino AS ip_tenant_approval,
    vistoria.ipAprovacaoProprietario AS ip_owner_approval,
    vistoria.soAprovacaoInquilino AS os_tenant_approval,
    vistoria.soAprovacaoProprietario AS os_owner_approval,
    vistoria.atualizadoEm AS ts_updated,
    vistoria.expiraEm AS ts_expired,
    vistoria.ref_id AS id_ref,
    vistoria.tipo AS type,
    vistoria.shortRevisarInq AS short_review_tenant,
    vistoria.shortRevisarProp AS short_review_owner,
    vistoria.finalReportPdfId AS id_final_report_pdf,
    vistoria.finalReportSentAt AS dt_final_report_sent,
    vistoria.itenCommented AS is_item_commented,
    vistoria.finalReportCreated AS is_final_report_created,
    vistoria.lastReportSent AS last_report_sent,
    vistoria.reportFinished AS is_report_finished,
    vistoria.keyLocation AS key_location,
    vistoria.keyLocationDetails AS key_location_details,
    vistoria.inspectorGotAllInfo AS has_inspector_got_all_info,
    vistoria.partialTenantReportSentAt AS ts_partial_tenant_report_sent,
    vistoria.partialOwnerReportSentAt AS ts_partial_owner_report_sent,
    vistoria.version,
    vistoria.schedule_id AS id_booking,
    vistoria.scheduleObservations AS schedule_observations,
    vistoria.reportRevised AS report_revised,
    vistoria.scheduleDoubleChecked AS is_schedule_double_checked,
    coalesce(has_inspector_comment, false) AS has_inspector_comment,
    coalesce(has_tenant_comment, false) AS has_tenant_comment,
    coalesce(has_owner_comment, false) AS has_owner_comment
FROM
    datalake_ebdb_raw.vistoria AS vistoria
    LEFT JOIN comments
        ON vistoria.id = comments.vistoria_id
