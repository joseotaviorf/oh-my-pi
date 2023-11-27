WITH last_extracted AS (
    SELECT
        id_group,
        name,
        dt_extracted
    FROM
        datalake_velo_zendesk_clean.groups
    QUALIFY
        ROW_NUMBER() OVER(PARTITION BY id_group ORDER BY dt_extracted DESC) = 1
    )

    SELECT
        th.id_ticket,
        th.id_assignee,
        th.id_group,
        th.id_requester,
        th.id_submitter,
        le.name,
        th.priority,
        REPLACE(REPLACE(SPLIT(th.satisfaction_rating, ':')[1],'}}',''),'"','') AS satisfaction_rating,
        ROW_NUMBER() OVER(PARTITION BY th.id_ticket ORDER BY th.ts_updated DESC) AS ticket_order,
        th.subject,
        th.status,
        th.dt_extracted,
        th.ts_created,
        th.ts_created_local,
        th.ts_updated,
        FROM_UTC_TIMESTAMP(th.ts_updated, 'Brazil/East') AS ts_updated_local,
        th.ts_load

    FROM
        datalake_velo_zendesk_clean.tickets_history th
    LEFT JOIN
        last_extracted le
        ON le.id_group = th.id_group
