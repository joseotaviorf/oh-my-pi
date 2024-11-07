WITH contracts AS (
    SELECT
        turf.id_task AS sk_task,
        turf.id_workgroup AS sk_workgroup,
        turf.id_receiver AS sk_receiver,
        turf.id_start_date AS sk_start_date,
        turf.id_completed_date AS sk_completed_date,
        turf.id_origin AS sk_origin,
        turf.id_assignee AS sk_assignee,
        turf.id_user_action AS sk_user_action,
        COALESCE(ec.id, ib1.id_contract, ib2.id_contract, -1) AS sk_contract,
        COALESCE(ib1.id_external, ib2.id_external, -1) AS sk_inspection,
        turf.id_action_date AS sk_action_date,
        turf.id_task_user_start_date AS sk_task_action_start_date,
        turf.id_task_user_end_date AS sk_task_action_end_date,
        turf.action_user_name,
        turf.action_type,
        turf.origin,
        turf.task_user_type AS task_action_type,
        turf.task_user_resolve_hours AS task_user_action_resolve_hours,
        turf.ts_action,
        turf.ts_task_user_start AS ts_task_action_start,
        turf.ts_task_user_end AS ts_task_action_end,
        turf.year,
        turf.month,
        turf.day
    FROM
        datalake_crm_tasks_flows.tasks_users_resolutions_flow AS turf
    LEFT JOIN
        datalake_ebdb_clean.contract AS ec
            ON turf.origin = 'Contrato'
            AND turf.id_origin = ec.id
    LEFT JOIN
        datalake_inspections.inspection_booking AS ib1
            ON turf.origin = 'Vistoria'
            AND INT(turf.id_origin) IS NOT NULL
            AND turf.id_origin = ib1.id_external
    LEFT JOIN
        datalake_inspections.inspection_booking AS ib2
            ON turf.origin = 'Vistoria'
            AND INT(turf.id_origin) IS NULL
            AND turf.id_origin = ib2.id_client_side
    WHERE
        (
        turf.type IN (
            'AgendarVistoria',
            'AgendarVistoriaPreSaida',
            'AgendarVistoriaSaida',
            'AnalisarPreVistoria',
            'AnaliseVistoriaSaida',
            'CancelarVistoriaPreSaida',
            'ConfirmarVistoriaEntrada',
            'ConfirmarVistoriaPreSaida',
            'ConfirmarVistoriaSaida',
            'EnviarPrimeiroResultadoSaida',
            'EnviarSegundoResultadoSaida',
            'EnviarVistoria',
            'FollowUpVistoriaEntrada',
            'FollowUpVistoriaPreSaida',
            'FollowUpVistoriaSaida',
            'InspectionRescheduled',
            'PrimeiraAnaliseVistoriaSaida',
            'SegundaAnaliseVistoriaSaida'
        )
        OR (
            turf.type = 'Manual'
            AND turf.id_workgroup IN (
                'DEP_VISTORIA_ID',
                'DEP_VISTORIA_LAUDO',
                'DEP_VISTORIA_OFFBOARDING',
                'EXIT_INSPECTION_TEAM',
                'REVISIT_POSTCONTRACT_TEAM'
            )
        )
    )
    AND turf.year = {year}
    AND turf.month = {month}
    AND turf.day = {day}
),
contract_house_listing AS (
    SELECT DISTINCT
        COALESCE(lc.id_house_listing, -1) AS sk_house_listing,
        COALESCE(lc.id_contract, -1) AS sk_contract,
        COALESCE(rf.id_owner, -1) AS sk_house_owner,
        COALESCE(rf.id_client, -1) AS sk_tenant
    FROM
        datalake_listing_contracts.listing_contracts AS lc
    LEFT JOIN
        datalake_ebdb_rent_flow.rent_flow AS rf
        ON rf.id_contract = lc.id_contract
)
SELECT DISTINCT
    c.sk_task,
    c.sk_receiver,
    COALESCE(c.sk_origin, -1) AS sk_origin,
    c.sk_assignee,
    c.sk_user_action,
    c.sk_inspection,
    c.sk_contract,
    COALESCE(chl.sk_house_listing, -1) AS sk_house_listing,
    COALESCE(chl.sk_house_owner, -1) AS sk_house_owner,
    COALESCE(chl.sk_tenant, -1) AS sk_tenant,
    c.sk_start_date,
    c.sk_completed_date,
    c.sk_action_date,
    c.sk_task_action_start_date,
    c.sk_task_action_end_date,
    c.action_user_name,
    c.action_type,
    c.task_action_type,
    c.task_user_action_resolve_hours,
    c.ts_action,
    c.ts_task_action_start,
    c.ts_task_action_end,
    NOW() AS ts_load,
    c.year,
    c.month,
    c.day
FROM
    contracts AS c
LEFT JOIN
    contract_house_listing AS chl
        ON c.sk_contract = chl.sk_contract
        AND c.sk_contract != -1