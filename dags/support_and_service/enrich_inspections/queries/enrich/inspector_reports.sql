WITH inspection AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.inspection_aud
    WHERE
        MAKE_DATE(year, month, day) BETWEEN '{load_start_date}' AND '{load_end_date}'
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_inspection ORDER BY ts_updated DESC) = 1
),
appointment AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.appointment_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_inspection ORDER BY ts_updated DESC) = 1
),
assessment AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.assessment_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_assessment ORDER BY ts_updated DESC) = 1
),
room AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.room_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_room ORDER BY ts_updated DESC) = 1
),
issue_type AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.issue_type_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_issue_type ORDER BY ts_updated DESC) = 1
),
item_type AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.item_type_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_item_type ORDER BY ts_updated DESC) = 1
),
room_type AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.room_type_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_room_type ORDER BY ts_updated DESC) = 1
),
item_group_type AS (
    SELECT
        *
    FROM
        datalake_inspection_services_clean.item_group_type_aud
    QUALIFY
        ROW_NUMBER() OVER (PARTITION BY id_item_group_type ORDER BY ts_updated DESC) = 1
)
SELECT DISTINCT
    MD5(
      COALESCE(ia.id_inspection, 'N/A')
      || COALESCE(ia.id_inspector, 'N/A')
      || COALESCE(ia.id_contract, 'N/A')
      || COALESCE(aa.id_appointment, 'N/A')
      || COALESCE(ra.id_room, 'N/A')
      || COALESCE(it.id_item, 'N/A')
      || COALESCE(ig.id_item_group, 'N/A')
      || COALESCE(ii.id_item_issue, 'N/A')
      || COALESCE(im.id_item_media, 'N/A')
    ) AS id_report,
    ia.id_inspection,
    ia.id_inspector,
    ia.id_contract,
    aa.id_appointment,
    ra.id_room,
    it.id_item,
    ig.id_item_group,
    ii.id_item_issue,
    im.id_item_media,
    ia.type AS inspection_type,
    room_type.type AS room_type,
    item_group_type.type AS item_group_type,
    item_type.type AS item_type,
    ita.type AS issue_type,
    im.type AS media_type,
    ig.status AS item_group_status,
    it.status AS item_status,
    NULLIF(it.comment, '') AS item_comment,
    NULLIF(ii.comment, '') AS issue_comment,
    ra.room_name,
    ig.name AS item_group_name,
    it.is_present AS is_present_item,
    ass.ts_created AS ts_synced,
    ia.year,
    ia.month,
    ia.day
FROM
    inspection AS ia
LEFT JOIN
    appointment AS aa
      ON ia.id_inspection = aa.id_inspection
LEFT JOIN
    assessment AS ass
      ON ia.id_inspection = ass.id_inspection
LEFT JOIN
    room AS ra
      ON ass.id_assessment = ra.id_assessment
LEFT JOIN
    datalake_inspection_services_clean.item_group_aud AS ig
      ON ra.id_room = ig.id_room
      AND ig.is_active_status IS NULL AND ig.is_active_inferior_quality IS NULL
LEFT JOIN
    datalake_inspection_services_clean.item_aud AS it
      ON ig.id_item_group = it.id_item_group
      AND it.is_active IS NULL
LEFT JOIN
    datalake_inspection_services_clean.item_issue_aud AS ii
      ON it.id_item = ii.id_item
      AND ii.is_active IS NULL
LEFT JOIN
    datalake_inspection_services_clean.item_media_aud AS im
      ON it.id_item = im.id_item
      AND im.is_active IS NULL
LEFT JOIN
    issue_type AS ita
      ON ii.id_type = ita.id_issue_type
LEFT JOIN
    item_type
      ON it.id_type = item_type.id_item_type
LEFT JOIN
    room_type
      ON ra.id_type = room_type.id_room_type
LEFT JOIN
    item_group_type
      ON ig.id_type = item_group_type.id_item_group_type
