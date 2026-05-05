WITH deduped_business_rules_groups AS (
    SELECT
        src.id_business_rules_group,
        src.group_name,
        src.group_status,
        src.user_profiles_count,
        src.is_default_group,
        src.ts_created,
        src.ts_updated,
        src.business_rules,
        src.ts_load
    FROM
        datalake_oitchau_clean.business_rules_groups AS src
    WHERE
        MAKE_DATE(src.year, src.month, src.day) BETWEEN DATE('{load_start_date}')
            AND DATE('{load_end_date}')
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                src.id_business_rules_group
            ORDER BY
                src.ts_load DESC NULLS LAST,
                src.year DESC,
                src.month DESC,
                src.day DESC
        ) = 1
),
business_rules_with_version_arrays AS (
    SELECT
        dg.group_name,
        dg.group_status,
        dg.user_profiles_count,
        dg.is_default_group,
        dg.ts_created,
        dg.ts_updated,
        dg.ts_load,
        dg.business_rules AS rule_versions
    FROM
        deduped_business_rules_groups AS dg
),
payovertime_rule_versions_exploded AS (
    SELECT
        bv.group_name,
        bv.group_status,
        bv.user_profiles_count,
        bv.is_default_group,
        bv.ts_created,
        bv.ts_updated,
        bv.ts_load,
        brv.rules.payedOvertime.splitDaysBasedOn AS split_days_based_on,
        brv.rules.payedOvertime.phasesType AS phases_type,
        brv.rules.payedOvertime.weekdayStage AS weekday_stage,
        brv.rules.payedOvertime.holidayStage AS holiday_stage,
        brv.rules.payedOvertime.missingDayStrategy AS missing_day_strategy,
        brv.rules.payedOvertime.ignoreOvertimeOnNonPlannedDays AS ignore_overtime_on_non_planned_days,
        brv.rules.payedOvertime.hoursBankRecurrencePeriod AS hours_bank_recurrence_period,
        brv.rules.payedOvertime.hoursBankRecurrenceInterval AS hours_bank_recurrence_interval,
        brv.rules.payedOvertime.hoursBankResetType AS hours_bank_reset_type,
        brv.rules.payedOvertime.hoursBankBalanceAlert.active AS hours_bank_balance_alert_active,
        brv.rules.payedOvertime.hoursBankBalanceAlert.limit AS hours_bank_balance_alert_limit,
        brv.rules.payedOvertime.hoursBankBalanceAlert.limitType AS hours_bank_balance_alert_limit_type,
        brv.rules.payedOvertime.extraHoursBalanceAlert.active AS extra_hours_balance_alert_active,
        brv.rules.payedOvertime.extraHoursBalanceAlert.limit AS extra_hours_balance_alert_limit,
        brv.rules.payedOvertime.extraHoursBalanceAlert.limitType AS extra_hours_balance_alert_limit_type,
        brv.rules.payedOvertime.phases AS rule_segments
    FROM
        business_rules_with_version_arrays AS bv
    LATERAL VIEW
        EXPLODE_OUTER(bv.rule_versions) rv AS brv
    WHERE
        brv.rules IS NOT NULL
        AND brv.rules.payedOvertime IS NOT NULL
        AND brv.rules.payedOvertime.phases IS NOT NULL
),
hours_bank_phase_segments_exploded AS (
    SELECT
        pe.group_name,
        pe.group_status,
        pe.user_profiles_count,
        pe.is_default_group,
        pe.ts_created,
        pe.ts_updated,
        pe.ts_load,
        pe.split_days_based_on,
        pe.phases_type,
        pe.weekday_stage,
        pe.holiday_stage,
        pe.missing_day_strategy,
        pe.ignore_overtime_on_non_planned_days,
        pe.hours_bank_recurrence_period,
        pe.hours_bank_recurrence_interval,
        pe.hours_bank_reset_type,
        pe.hours_bank_balance_alert_active,
        pe.hours_bank_balance_alert_limit,
        pe.hours_bank_balance_alert_limit_type,
        pe.extra_hours_balance_alert_active,
        pe.extra_hours_balance_alert_limit,
        pe.extra_hours_balance_alert_limit_type,
        sr.uuid AS hours_bank_rule_key,
        sr.name AS segment_label,
        sr.type AS segment_type,
        sr.limit AS segment_limit_minutes,
        sr.extraHours AS segment_extra_hours,
        sr.daysMask AS days_mask,
        sr.dayTypeBasedOnSchedule AS day_type_based_on_schedule
    FROM
        payovertime_rule_versions_exploded AS pe
    LATERAL VIEW
        EXPLODE_OUTER(pe.rule_segments) sg AS sr
),
hours_bank_rule_segments_deduplicated AS (
    SELECT
        ps.group_name,
        ps.group_status,
        ps.user_profiles_count,
        ps.is_default_group,
        ps.ts_created,
        ps.ts_updated,
        ps.ts_load,
        ps.split_days_based_on,
        ps.phases_type,
        ps.weekday_stage,
        ps.holiday_stage,
        ps.missing_day_strategy,
        ps.ignore_overtime_on_non_planned_days,
        ps.hours_bank_recurrence_period,
        ps.hours_bank_recurrence_interval,
        ps.hours_bank_reset_type,
        ps.hours_bank_balance_alert_active,
        ps.hours_bank_balance_alert_limit,
        ps.hours_bank_balance_alert_limit_type,
        ps.extra_hours_balance_alert_active,
        ps.extra_hours_balance_alert_limit,
        ps.extra_hours_balance_alert_limit_type,
        ps.hours_bank_rule_key,
        ps.segment_label,
        ps.segment_type,
        ps.segment_limit_minutes,
        ps.segment_extra_hours,
        ps.days_mask,
        ps.day_type_based_on_schedule
    FROM
        hours_bank_phase_segments_exploded AS ps
    WHERE
        ps.hours_bank_rule_key IS NOT NULL
        AND TRIM(ps.hours_bank_rule_key) <> ''
    QUALIFY
        ROW_NUMBER() OVER (
            PARTITION BY
                ps.hours_bank_rule_key
            ORDER BY
                ps.ts_load DESC NULLS LAST
        ) = 1
)
SELECT
    XXHASH64(
        hr.hours_bank_rule_key
    ) AS sk_hours_bank_rule,
    hr.hours_bank_rule_key,
    hr.group_name,
    hr.group_status,
    hr.segment_label,
    hr.segment_type,
    hr.days_mask,
    hr.day_type_based_on_schedule,
    hr.split_days_based_on,
    hr.phases_type,
    hr.weekday_stage,
    hr.holiday_stage,
    hr.missing_day_strategy,
    hr.hours_bank_recurrence_period,
    hr.hours_bank_recurrence_interval,
    hr.hours_bank_reset_type,
    hr.hours_bank_balance_alert_limit,
    hr.hours_bank_balance_alert_limit_type,
    hr.extra_hours_balance_alert_limit,
    hr.extra_hours_balance_alert_limit_type,
    hr.user_profiles_count,
    hr.segment_limit_minutes,
    hr.segment_extra_hours,
    hr.is_default_group,
    hr.ignore_overtime_on_non_planned_days,
    hr.hours_bank_balance_alert_active,
    hr.extra_hours_balance_alert_active,
    DATE(hr.ts_created) AS dt_created,
    DATE(hr.ts_updated) AS dt_updated,
    hr.ts_created,
    hr.ts_updated,
    CURRENT_TIMESTAMP() AS ts_load
FROM
    hours_bank_rule_segments_deduplicated AS hr
