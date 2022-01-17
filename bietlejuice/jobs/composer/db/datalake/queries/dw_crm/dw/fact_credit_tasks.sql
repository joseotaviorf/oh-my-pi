WITH proposals AS (
    SELECT
        turf.id_task AS sk_task,
        turf.id_workgroup AS sk_workgroup,
        turf.id_receiver AS sk_receiver,
        turf.id_start_date AS sk_start_date,
        turf.id_completed_date AS sk_completed_date,
        turf.id_origin AS sk_origin,
        turf.id_assignee AS sk_assignee,
        CAST(COALESCE(epi.id_user, -1) AS BIGINT) AS sk_house_owner,
        CAST(COALESCE(ep.id_proponent, -1) AS BIGINT) AS sk_proponent,
        CAST(COALESCE(ep.id, -1) AS BIGINT) AS sk_proposal,
        turf.id_user_action AS sk_user_action,
        turf.id_action_date AS sk_action_date,
        turf.id_task_user_start_date AS sk_task_user_start_date,
        turf.id_task_user_end_date AS sk_task_user_end_date,
        turf.action_user_name,
        turf.action_type,
        turf.origin,
        turf.task_user_type,
        turf.task_user_resolve_hours,
        turf.ts_action,
        turf.ts_task_user_start,
        turf.ts_task_user_end,
        turf.year,
        turf.month,
        turf.day
    FROM
        datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
    LEFT JOIN
        datalake_ebdb_clean.proposal AS ep
            ON turf.origin = 'Proposta'
            AND turf.id_origin = ep.id
    LEFT JOIN
        datalake_ebdb_clean.house AS epi
            ON epi.id = ep.id_house
    WHERE
        turf.type IN ('EnviarCardiff')
        AND turf.year = {year}
        AND turf.month = {month}
        AND turf.day = {day}
),
proposal_house_listing AS (
    SELECT
        CAST(sk_house_listing AS BIGINT) AS sk_house_listing,
        CAST(sk_proposal AS BIGINT) AS sk_proposal,
        CAST(sk_client AS BIGINT) AS sk_proponent
    FROM
        dw_public.fact_listing_rent_flows
    WHERE
        sk_proposal != '-1'
    GROUP BY 1, 2, 3
)
SELECT DISTINCT
    p.sk_task,
    p.sk_receiver,
    COALESCE(CAST(p.sk_origin AS BIGINT), -1) AS sk_origin,
    p.sk_assignee,
    p.sk_user_action,
    p.sk_proposal,
    COALESCE(phl.sk_house_listing, -1) AS sk_house_listing,
    p.sk_house_owner,
    COALESCE(phl.sk_proponent, p.sk_proponent) AS sk_proponent,
    p.sk_start_date,
    p.sk_completed_date,
    p.sk_action_date,
    p.sk_task_user_start_date,
    p.sk_task_user_end_date,
    p.action_user_name,
    p.action_type,
    p.task_user_type,
    p.task_user_resolve_hours,
    p.ts_action,
    p.ts_task_user_start,
    p.ts_task_user_end,
    NOW() AS ts_load,
    p.year,
    p.month,
    p.day
FROM
    proposals AS p
LEFT JOIN
    proposal_house_listing AS phl
        ON p.sk_proposal = phl.sk_proposal
        AND p.sk_proposal != -1