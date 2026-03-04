SELECT
    CSCASENO AS id_case,
    CSSTGID AS id_stage,
    CSTYPE AS id_case_type,
    CSDESC AS stage_description,
    CSORDER AS stage_order,
    CSSUBTYPE AS case_subtype,
    CASE
        WHEN CSTATUS = 'R' THEN 'Current'
        WHEN CSTATUS = 'S' THEN 'Scheduled'
        WHEN CSTATUS = 'E' THEN 'Completed'
        ELSE CSTATUS
    END AS stage_status,
    CSAMT AS authorized_expenses_amount,
    CSDAYS AS required_days_for_stage,
    CSRESPDAYS AS responsible_attorney_days,
    CSSUPVDAYS AS supervisor_attorney_days,
    CSPREDYS AS max_previous_system_days,
    CSPOSDYS AS max_post_system_days,
    CSSTDT AS dt_stage_start,
    CSENDDT AS dt_stage_end,
    CSDTUPD AS ts_updated,
    NOW() AS ts_load
FROM datalake_cyber_legal_raw.casestag
