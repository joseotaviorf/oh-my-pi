WITH sla_target AS (
    SELECT DISTINCT
        SPLIT(team, ' - ')[0] AS service_type,
        CASE
            WHEN LOWER(team) LIKE "%saida%" THEN "offboarding"
            WHEN LOWER(team) LIKE "%entrada%" THEN "onboarding"
            ELSE NULL
        END AS inspection_type,
        team,
        CAST(target AS INT) AS target,
        CASE
            WHEN CAST(target AS INT) < 0 THEN CAST(target AS INT)
            ELSE 0
        END negative_target_days,
        CASE
            WHEN CAST(target AS INT) < 0 THEN NEGATIVE(CAST(target AS INT))
            ELSE CAST(target AS INT)
        END reference_target_days,
        dt_target
    FROM
        datalake_support_and_service_kpis_targets.kpis_targets AS kt
    WHERE
        metric_name = "LDT"
        AND target IS NOT NULL
        AND LOWER(team) LIKE "vistoria%"
        AND granularity = "week"
)
SELECT
    i.id_inspection,
    i.id_assessment,
    i.id_external,
    i.id_city,
    i.city_name,
    i.inspection_type,
    i.status,
    st.target AS sla_execution_target,
    CASE
        WHEN i.assessment_source = 'INSPECTORS_FLUTTER'
            THEN timestampdiff(HOUR, i.ts_execution_started_local_tz, i.ts_execution_finished_local_tz)
        ELSE NULL
    END AS ldt_hours_execution,
    CASE
        WHEN i.status == "cancelled" THEN FALSE
        WHEN DATE(i.ts_inspected) IS NULL THEN NULL
        WHEN i.inspection_type = "offboarding"
            AND i.ts_termination_canceled IS NULL
            AND DATE(i.ts_inspected) <= cc.dt_workday
            THEN TRUE
        WHEN i.inspection_type = "onboarding"
            AND DATE(i.ts_inspected) <= cc.dt_workday
            THEN TRUE
        ELSE FALSE
    END AS is_sla_execution,
    i.dt_execution_limit,
    i.ts_execution_started_local_tz,
    i.ts_execution_finished_local_tz,
    i.ts_inspected,
    i.ts_created,
    i.ts_updated
FROM
    datalake_inspections.inspection_booking AS i
JOIN
    sla_target AS st
        ON LOWER(st.team) LIKE CONCAT("% - ", LOWER(i.city_name))
        AND st.inspection_type = i.inspection_type
        AND st.dt_target = DATE(i.ts_created)
LEFT JOIN
    datalake_date.cities_calendar AS cc
        ON cc.dt_reference = DATE_ADD(i.dt_execution_limit, st.negative_target_days)
        AND cc.id_city = i.id_city
        AND cc.count_workdays = st.reference_target_days