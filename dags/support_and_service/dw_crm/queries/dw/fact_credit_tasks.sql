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
house_listing AS (
    SELECT
        hl.id_house_listing,
        hl.id_contract,
        hl.id_house,
        hl.ts_listing_version_start,
        COALESCE(hl.ts_listing_version_end, NOW()) AS ts_listing_version_end
    FROM
        datalake_ebdb_listing.house_listing AS hl
    UNION
    SELECT
        lc.id_house_listing,
        lc.id_contract,
        lc.id_house,
        lc.ts_listing_version_started AS ts_listing_version_start,
        lc.ts_listing_version_ended AS ts_listing_version_end
    FROM
        datalake_listing_contracts.listing_contracts AS lc
),
rent_flow_house_listing_matches AS (
    SELECT
        hl.id_house_listing,
        rf.id_proposal,
        rf.id_client
    FROM
        house_listing AS hl
    INNER JOIN
        datalake_ebdb_rent_flow.rent_flow AS rf
            ON rf.id_contract = hl.id_contract

    UNION

    SELECT
        hl.id_house_listing,
        rf.id_proposal,
        rf.id_client
    FROM
        house_listing AS hl
    INNER JOIN
        datalake_ebdb_rent_flow.rent_flow AS rf
            ON rf.id_house = hl.id_house
    WHERE
        rf.dt_rent_flow_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
),
proposal_house_listing AS (
    SELECT DISTINCT
        COALESCE(matched.id_house_listing, -1) AS sk_house_listing,
        COALESCE(matched.id_proposal, -1) AS sk_proposal,
        COALESCE(matched.id_client, -1) AS sk_proponent
    FROM
        rent_flow_house_listing_matches AS matched
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