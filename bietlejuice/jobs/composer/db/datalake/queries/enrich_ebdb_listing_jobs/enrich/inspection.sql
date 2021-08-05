WITH
    comments AS (
        SELECT
            id_inspection,
            MAX(comment IS NOT NULL) AS has_inspector_comment,
            MAX(tenant_comment IS NOT NULL) AS has_tenant_comment,
            MAX(owner_comment IS NOT NULL) AS has_owner_comment
        FROM
            datalake_ebdb_clean.inspection_item
        GROUP BY
            id_inspection
    ),
    inspection_aud_sync as(
        SELECT DISTINCT
            ia.id_inspection,
            FIRST_VALUE(ia.ts_last_synced) OVER w AS ts_first_synced,
            LAST_VALUE(ia.ts_last_synced) OVER w AS ts_last_synced
        FROM
            datalake_ebdb_clean.inspection_aud ia
        WHERE
            ia.status = 'Revisada'
        WINDOW w AS (
            PARTITION BY ia.id_inspection, status
            ORDER BY ia.ts_last_synced
            ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING
        )
)
SELECT
    i.id,
    i.id_house,
    i.id_user_inspector,
    i.id_contract,
    i.id_booking,
    i.id_ref,
    i.id_final_report_pdf,
    i.status,
    i.mode,
    i.comment,
    i.hash,
    i.browser_tenant_approval,
    i.browser_owner_approval,
    i.tenant_comment,
    i.owner_comment,
    i.ip_tenant_approval,
    i.ip_owner_approval,
    i.os_tenant_approval,
    i.os_owner_approval,
    i.type,
    i.short_review_tenant,
    i.short_review_owner,
    i.last_report_sent,
    i.key_location,
    i.key_location_details,
    i.version,
    i.schedule_observations,
    i.report_revised,
    i.is_tenant_approved,
    i.is_owner_approved,
    i.is_schedule_double_checked,
    i.is_report_finished,
    i.is_item_commented,
    i.is_final_report_created,
    COALESCE(c.has_inspector_comment, FALSE) AS has_inspector_comment,
    COALESCE(c.has_tenant_comment, FALSE) AS has_tenant_comment,
    COALESCE(c.has_owner_comment, FALSE) AS has_owner_comment,
    i.has_inspector_got_all_info,
    i.dt_final_report_sent,
    i.dt_inspected,
    i.ts_tenant_approved,
    i.ts_owner_approved,
    i.ts_partial_tenant_report_sent,
    i.ts_partial_owner_report_sent,
    i.ts_created,
    i.ts_expired,
    i.ts_updated,
    ias.ts_first_synced,
    ias.ts_last_synced
FROM
    datalake_ebdb_clean.inspection AS i
    LEFT JOIN comments c
        ON i.id = c.id_inspection
    LEFT JOIN inspection_aud_sync ias
        ON i.id = ias.id_inspection
