WITH main_inspection_aud_sync as(
    SELECT DISTINCT
        ia.id_inspection,
        FIRST_VALUE(ia.ts_last_synced) OVER (PARTITION BY ia.id_inspection, status ORDER BY ia.ts_last_synced ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS ts_first_synced
    FROM
        datalake_ebdb_clean.inspection_aud ia
    WHERE
        ia.status = 'Revisada'
),
last_inspection_update AS (
    SELECT
        *
    FROM
        datalake_inspections_clean.inspection_aud AS ia
    QUALIFY
        ia.ts_updated = FIRST(ia.ts_updated) OVER (PARTITION BY ia.id_inspection ORDER BY ia.ts_updated DESC)
),
main_exception AS (
    SELECT
        DISTINCT i.id AS id_inspection
    FROM
        datalake_ebdb_clean.inspection AS i
    EXCEPT
    SELECT
        DISTINCT i.id_external AS id_inspection
    FROM
        last_inspection_update AS i
)
SELECT
    MD5(CONCAT(i.id, 'PWA')) AS id_inspection,
    i.id AS id_external,
    i.id_user_inspector AS id_inspector,
    i.id_booking,
    MD5(CONCAT(i.id_booking, 'PWA')) AS id_appointment,
    i.id_contract,
    i.id_house,
    CASE
        WHEN i.type = 'Entrada' THEN 'onboarding'
        WHEN i.type = 'Saida' THEN 'offboarding'
        WHEN i.type = 'Constatacao' THEN 'verification'
        WHEN i.type = 'Portabilidade' THEN 'portability'
        ELSE NULL
    END inspection_type,
    CASE
        WHEN i.status = 'Agendada' THEN 'scheduled'
        WHEN i.status = 'Cancelada' THEN 'cancelled'
        WHEN i.status IN ('Revisada' , 'EmRevisao') THEN 'reviewed'
        ELSE i.status
    END AS status,
    TIMESTAMP(i.dt_inspected) AS ts_inspected,
    i.ts_created,
    i.ts_updated,
    m.ts_first_synced
FROM
    main_exception AS me
JOIN
    datalake_ebdb_clean.inspection AS i
      ON me.id_inspection = i.id
LEFT JOIN
    main_inspection_aud_sync AS m
      ON i.id = m.id_inspection
