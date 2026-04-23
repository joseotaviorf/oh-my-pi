SELECT
    uuid AS id_business_rules_group,
    companyUuid AS id_company,
    externalId AS id_external,
    createdBy AS id_created_by_user,
    updatedBy AS id_updated_by_user,
    name AS group_name,
    status AS group_status,
    userProfilesCount AS user_profiles_count,
    isDefault AS is_default_group,
    isLocked AS is_locked_for_editing,
    createdAt AS ts_created,
    updatedAt AS ts_updated,
    businessRules AS business_rules,
    ts_load,
    year,
    month,
    day
FROM
    datalake_oitchau_raw.business_rules_groups
