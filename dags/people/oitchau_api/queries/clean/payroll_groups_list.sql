SELECT
    uuid AS id_payroll_group_definition,
    companyUuid AS id_company,
    externalId AS id_external,
    createdBy AS id_created_by_user,
    name AS payroll_group_definition_name,
    status AS definition_status,
    recurrence AS recurrence_rule,
    isDefault AS is_default_definition,
    isLocked AS is_locked_for_editing,
    forDeactivatedProfile AS is_for_deactivated_profile,
    lastLockDate AS dt_last_locked,
    minUserProfileAssignmentDate AS dt_min_user_profile_assigned,
    nextStartDate AS dt_next_period_started,
    nextEndDate AS dt_next_period_ended,
    createdAt AS ts_created,
    updatedAt AS ts_updated,
    userProfilePayrollGroups AS user_profile_payroll_groups,
    ts_load,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.payroll_groups_list
