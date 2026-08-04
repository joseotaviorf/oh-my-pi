WITH ranked AS (
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
        year,
        month,
        day,
        NOW() AS ts_load,
        ROW_NUMBER() OVER(PARTITION BY CSCASENO, CSSTGID ORDER BY MAKE_DATE(year,month,day) DESC) AS rn
    FROM datalake_cyber_legal_raw.casestag
    WHERE
        MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
)
SELECT
    id_case,
    id_stage,
    id_case_type,
    stage_description,
    stage_order,
    case_subtype,
    stage_status,
    authorized_expenses_amount,
    required_days_for_stage,
    responsible_attorney_days,
    supervisor_attorney_days,
    max_previous_system_days,
    max_post_system_days,
    dt_stage_start,
    dt_stage_end,
    ts_updated,
    year,
    month,
    day,
    ts_load
FROM
    ranked
WHERE
    rn = 1
