WITH union_medias AS (
    SELECT
        rrm.id_repair_request_media AS id_media,
        rrm.id_main AS id_external_media,
        rr.id_reviewer,
        rrm.id_repair_request AS id_origin,
        rrm.uuid,
        "repair_request" AS origin,
        rrm.type AS media_type,
        rrm.name AS media_path,
        rrm.ts_created,
        rrm.ts_updated,
        rrm.year,
        rrm.month,
        rrm.day
    FROM
        datalake_inspections_clean.repair_request_media AS rrm
    JOIN
        datalake_inspections_clean.repair_request AS rr
        ON rr.id_repair_request = rrm.id_repair_request
    WHERE
        MAKE_DATE(rrm.year, rrm.month, rrm.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
    UNION ALL
    SELECT
        cm.id_contestation_media AS id_media,
        NULL AS id_external_media,
        c.id_reviewer,
        cm.id_contestation AS id_origin,
        cm.uuid,
        "contestation" AS origin,
        cm.type AS media_type,
        cm.name AS media_path,
        cm.ts_created,
        cm.ts_updated,
        cm.year,
        cm.month,
        cm.day
    FROM
        datalake_inspections_clean.contestation_media AS cm
    JOIN
        datalake_inspections_clean.contestation AS c
        ON c.id_contestation = cm.id_contestation
    WHERE
        MAKE_DATE(cm.year, cm.month, cm.day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT DISTINCT
    m.id_media,
    m.id_external_media,
    m.id_reviewer,
    m.id_origin,
    a.id_assessment,
    a.id_inspection,
    m.uuid,
    m.origin,
    r.reviewer_type,
    m.media_type,
    m.media_path,
    m.ts_created,
    m.ts_updated,
    m.year,
    m.month,
    m.day
FROM
    union_medias AS m
JOIN
    datalake_inspections_clean.reviewer AS r
        ON r.id_reviewer = m.id_reviewer
JOIN
    datalake_inspections_clean.assessment AS a
        ON a.id_assessment = r.id_assessment