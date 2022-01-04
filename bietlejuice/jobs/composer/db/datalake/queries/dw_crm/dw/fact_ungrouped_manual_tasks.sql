WITH contracts_offers AS (
    SELECT
        turf.id_task AS sk_task,
        turf.id_receiver AS sk_receiver,
        turf.id_origin AS sk_origin,
        turf.id_assignee AS sk_assignee,
        CAST(COALESCE(dc.sk_contract, CAST(ec.id AS STRING)) AS BIGINT) AS sk_contract,
        ep.id AS sk_proposal,
        CAST(COALESCE(eo.sk_offer, feo.sk_offer) AS BIGINT) AS sk_offer,
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
        dw_janus.dim_contract AS dc
            ON turf.origin = 'Contrato'
                AND turf.id_origin = dc.sk_contract
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
        dw_public.dim_offer AS eo
            ON turf.origin = 'Offer'
                AND turf.id_origin = eo.id_offer
    LEFT JOIN
        dw_public.dim_offer AS feo
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
contract_offer_house_listing AS (
    SELECT
        CAST(sk_house_listing AS BIGINT) AS sk_house_listing,
        CAST(sk_rent_flow AS BIGINT) AS sk_rent_flow,
        CAST(sk_offer AS BIGINT) AS sk_offer,
        CAST(sk_proposal AS BIGINT) AS sk_proposal,
        CAST(sk_owner AS BIGINT) AS sk_house_owner,
        CAST(COALESCE(IF(sk_contract != '-1', sk_client, sk_contract), '-1') AS BIGINT) AS sk_tenant,
        CAST(COALESCE(IF(sk_proposal != '-1', sk_client, sk_proposal), '-1') AS BIGINT) AS sk_proponent,
        MAX(CAST(sk_contract AS BIGINT)) AS sk_contract
    FROM
        testing_map_ods_from_s3.ods_fact_listing_rent_flows
    WHERE
        sk_contract != '-1'
        OR sk_offer != '-1'
    GROUP BY 1, 2, 3, 4, 5, 6, 7
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