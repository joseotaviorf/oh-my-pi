SELECT 
    ActionReasonId AS id_action_reason,
    ActionId AS id_action,
    ActionReasonCode AS action_reason_code,
    ActionReason AS action_reason,
    to_date(StartDate) AS dt_start,
    to_date(EndDate) AS dt_end,
    ts_load
FROM datalake_hr_system_raw.action_reasons_lov