SELECT
    i.id_item AS sk_item,
    i.id_previous_item AS sk_previous_item,
    i.id_item_group AS sk_item_group,
    i.id_room AS sk_room,
    i.id_assessment AS sk_assessment,
    i.total_item_issue,
    i.total_media,
    i.total_inspector_comment,
    i.total_tenant_comment,
    i.total_owner_comment,
    i.has_media,
    i.has_inspector_comment,
    i.has_tenant_comment,
    i.has_owner_comment,
    i.ts_created,
    i.ts_updated,
    i.year,
    i.month,
    i.day
FROM
    datalake_inspections_metrics.item_description i
QUALIFY
    i.ts_updated = FIRST(i.ts_updated) OVER(PARTITION BY i.id_item ORDER BY i.ts_updated DESC)
