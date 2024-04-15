SELECT 
    ActionId AS id_action,
    ActionTypeId AS id_action_type,
    ActionCode AS action_code,
    ActionName AS action_name,
    Description AS description,
    ActionTypeCode AS action_type_code,
    TerminationType AS termination_type,
    CASE 
    WHEN UsedInContract = 'Y'
        THEN TRUE
    WHEN UsedInContract = 'N'
        THEN FALSE
    END AS is_used_in_contract,
    date(StartDate) AS dt_start,
    date(EndDate) AS dt_end,
    ts_load
FROM datalake_hr_system_raw.actions_lov