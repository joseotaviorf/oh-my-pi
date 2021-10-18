WITH contracts AS (
    SELECT
        turf.id_action_date AS sk_action_date,
        turf.id_assignee AS sk_assignee,
        turf.id_completed_date AS sk_completed_date,
        COALESCE(dc.sk_contract, '-1') AS sk_contract,
        turf.id_origin AS sk_origin,
        turf.id_receiver AS sk_receiver,
        turf.id_start_date AS sk_start_date,
        turf.id_task AS sk_task,
        turf.id_task_user_end_date AS sk_task_user_end_date,
        turf.id_task_user_start_date AS sk_task_user_start_date,
        turf.id_user_action AS sk_user_action,
        turf.action_type,
        turf.action_user_name,
        turf.task_user_type,
        turf.task_user_resolve_hours,
        turf.ts_action,
        turf.ts_task_user_end,
        turf.ts_task_user_start,
        turf.year,
        turf.month,
        turf.day
    FROM 
        datalake_crm_tasks_flows.tasks_users_resolutions_flow turf
    LEFT JOIN 
        dw_janus.dim_contract dc
            ON turf.origin = 'Contrato'
            AND CAST(CAST(turf.id_origin AS DECIMAL) AS BIGINT) = CAST(dc.sk_contract AS BIGINT)
    WHERE
        turf.year = {year}
        AND turf.month = {month}
        AND turf.day = {day}
        AND turf.id_workgroup IN (
                            'DEP_MEDIACAO_POS_CONTRATO_ID',
                            'PROTECTION_CUSTOMERS',
                            'PROTECTION_PARTNERS'
                            )
),
contract_house_listing AS (
    SELECT
        CAST(sk_contract AS BIGINT) AS sk_contract,
        CAST(sk_house_listing AS BIGINT) AS sk_house_listing,
        CAST(sk_owner AS BIGINT) AS sk_house_owner,
        CAST(sk_client AS BIGINT) AS sk_tenant
    FROM 
        testing_map_ods_from_s3.ods_fact_listing_rent_flows
    WHERE 
        sk_contract != '-1'
    GROUP BY 1, 2, 3, 4
)
SELECT DISTINCT
    c.sk_task,
    c.sk_action_date,
    c.sk_assignee,
    c.sk_completed_date,
    COALESCE(CAST(c.sk_contract AS BIGINT), -1) AS sk_contract,
    COALESCE(chl.sk_house_listing, -1) AS sk_house_listing,
    COALESCE(chl.sk_house_owner, -1) AS sk_house_owner,
    COALESCE(CAST(c.sk_origin AS BIGINT), -1) AS sk_origin,
    c.sk_receiver,
    c.sk_start_date,
    c.sk_task_user_end_date AS sk_task_action_end_date,
    c.sk_task_user_start_date AS sk_task_action_start_date,
    COALESCE(chl.sk_tenant, -1) AS sk_tenant,
    c.sk_user_action,
    c.action_type,
    c.action_user_name,
    c.task_user_type AS task_action_type,
    c.task_user_resolve_hours AS task_user_action_resolve_hours,
    c.ts_action,
    c.ts_task_user_end AS ts_task_action_end,
    c.ts_task_user_start AS ts_task_action_start,
    NOW() AS ts_load,
    c.year,
    c.month,
    c.day
FROM 
    contracts c
LEFT JOIN 
    contract_house_listing chl
        ON c.sk_contract = chl.sk_contract
        AND c.sk_contract != -1