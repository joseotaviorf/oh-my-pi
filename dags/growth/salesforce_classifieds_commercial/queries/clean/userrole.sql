SELECT
    Id AS id,
    ParentRoleId AS id_parent_role,
    ForecastUserId AS id_forecast_user,
    PortalAccountId AS id_portal_account,
    PortalAccountOwnerId AS id_portal_account_owner,
    LastModifiedById AS id_last_modified_by,
    Name AS role_name,
    DeveloperName AS developer_name,
    RollupDescription AS rollup_description,
    PortalType AS portal_type,
    CaseAccessForAccountOwner AS case_access_for_account_owner,
    ContactAccessForAccountOwner AS contact_access_for_account_owner,
    OpportunityAccessForAccountOwner AS opportunity_access_for_account_owner,
    MayForecastManagerShare AS may_forecast_manager_share,
    LastModifiedDate AS ts_last_modified,
    SystemModstamp AS ts_system_mod,
    CAST(LastModifiedDate AS DATE) AS dt_updated,
    YEAR(LastModifiedDate) AS year,
    MONTH(LastModifiedDate) AS month,
    DAY(LastModifiedDate) AS day
FROM
    datalake_salesforce_classifieds_raw.userrole
WHERE
    MAKE_DATE(year, month, day) BETWEEN DATE('{load_start_date}') AND DATE('{load_end_date}')
