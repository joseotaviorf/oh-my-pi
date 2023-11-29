WITH contracts_offers AS (
    SELECT
        turf.id_task AS sk_task,
        turf.id_receiver AS sk_receiver,
        turf.id_origin AS sk_origin,
        turf.id_assignee AS sk_assignee,
        CAST(COALESCE(dc.id, CAST(ec.id AS STRING)) AS BIGINT) AS sk_contract,
        ep.id AS sk_proposal,
        CAST(COALESCE(eo.id_offer_context, offer.id_offer_context, feo.id_offer_context) AS BIGINT) AS sk_offer,
        erf.id AS sk_rent_flow,
        turf.id_start_date AS sk_start_date,
        turf.id_completed_date AS sk_completed_date,
        turf.id_user_action AS sk_user_action,
        turf.id_action_date AS sk_action_date,
        turf.id_task_user_start_date AS sk_task_action_start_date,
        turf.id_task_user_end_date AS sk_task_action_end_date,
        turf.action_user_name,
        turf.action_type,
        turf.task_user_type AS task_action_type,
        turf.task_user_resolve_hours,
        turf.ts_action,
        turf.ts_task_user_start AS ts_task_action_start,
        turf.ts_task_user_end AS ts_task_action_end,
        turf.year,
        turf.month,
        turf.day
    FROM
        datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
    LEFT JOIN
        datalake_ebdb_clean.contract AS dc
            ON turf.origin = 'Contrato'
                AND turf.id_origin = dc.id
    LEFT JOIN
        datalake_ebdb_clean.pre_proposal AS epp
            ON turf.origin = 'PreProposta'
                AND turf.id_origin = epp.id
    LEFT JOIN
        datalake_ebdb_clean.proposal AS ep
            ON epp.id = ep.id_pre_proposal
    LEFT JOIN
        datalake_ebdb_clean.contract AS ec
            ON ep.id = ec.id_proposal
    LEFT JOIN
        datalake_ebdb_proposal.pre_proposal AS eo
            ON turf.origin = 'Offer'
                AND turf.id_origin = eo.id
    LEFT JOIN
        datalake_offer.offer AS offer
            ON turf.origin = 'Offer'
                AND turf.id_origin = offer.id
    LEFT JOIN
        datalake_offer.offer AS feo
            ON turf.origin = 'Offer'
                AND RLIKE(turf.id_origin, '\\D') = TRUE
                AND turf.id_origin = feo.id_firestore
    LEFT JOIN
        datalake_ebdb_clean.rent_flow AS erf
            ON turf.origin = 'FluxoLocacao'
                AND turf.id_origin = erf.id
    WHERE
        turf.type = 'Manual'
        AND turf.id_workgroup IS NULL
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
contract_offer_house_listing AS (
    SELECT DISTINCT
        COALESCE(hl.id_house_listing, -1) AS sk_house_listing,
        COALESCE(rf.id_rent_flow, -1) AS sk_rent_flow,
        COALESCE(rf.id_offer_context, -1) AS sk_offer,
        COALESCE(rf.id_proposal, -1) AS sk_proposal,
        COALESCE(rf.id_owner, -1) AS sk_house_owner,
        CASE
            WHEN rf.id_contract IS NOT NULL THEN rf.id_client
            ELSE -1
        END AS sk_tenant,
        CASE
            WHEN rf.id_proposal IS NOT NULL THEN rf.id_client
            ELSE -1
        END AS sk_proponent,
        COALESCE(rf.id_contract, -1) AS sk_contract
    FROM
        house_listing AS hl
    LEFT JOIN
        datalake_ebdb_rent_flow.rent_flow AS rf
            ON rf.id_contract = hl.id_contract
            OR (
                rf.id_house = hl.id_house
                AND rf.dt_rent_flow_created BETWEEN hl.ts_listing_version_start AND hl.ts_listing_version_end
            )
    WHERE
        rf.id_contract IS NOT NULL
        OR rf.id_offer_context IS NOT NULL
)
SELECT DISTINCT
    co.sk_task,
    co.sk_receiver,
    co.sk_start_date,
    co.sk_completed_date,
    COALESCE(CAST(co.sk_origin AS BIGINT), -1) AS sk_origin,
    co.sk_assignee,
    co.sk_user_action,
    COALESCE(co.sk_offer, chl_rent_flow.sk_offer, chl_contract.sk_offer, chl_offer.sk_offer, -1) AS sk_offer,
    COALESCE(co.sk_proposal, chl_rent_flow.sk_proposal, chl_contract.sk_proposal, chl_offer.sk_proposal, -1) AS sk_proposal,
    COALESCE(co.sk_contract, chl_rent_flow.sk_contract, chl_offer.sk_contract, -1) AS sk_contract,
    COALESCE(chl_rent_flow.sk_house_listing, chl_contract.sk_house_listing, chl_offer.sk_house_listing, -1) AS sk_house_listing,
    COALESCE(chl_rent_flow.sk_house_owner, chl_contract.sk_house_owner, chl_offer.sk_house_owner, -1) AS sk_house_owner,
    COALESCE(chl_rent_flow.sk_tenant, chl_contract.sk_tenant, chl_offer.sk_tenant, -1) AS sk_tenant,
    COALESCE(chl_rent_flow.sk_proponent, chl_contract.sk_proponent, chl_offer.sk_proponent, -1) AS sk_proponent,
    co.sk_action_date,
    co.sk_task_action_start_date,
    co.sk_task_action_end_date,
    co.action_user_name,
    co.action_type,
    co.task_action_type,
    co.task_user_resolve_hours AS task_user_action_resolve_hours,
    co.ts_action,
    co.ts_task_action_start,
    co.ts_task_action_end,
    NOW() AS ts_load,
    co.year,
    co.month,
    co.day
FROM
    contracts_offers AS co
LEFT JOIN
    contract_offer_house_listing AS chl_rent_flow
        ON co.sk_rent_flow = chl_rent_flow.sk_rent_flow
LEFT JOIN
    contract_offer_house_listing AS chl_contract
        ON co.sk_contract = chl_contract.sk_contract
LEFT JOIN
    contract_offer_house_listing AS chl_offer
        ON co.sk_offer = chl_offer.sk_offer