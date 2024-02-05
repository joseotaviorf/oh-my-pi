SELECT
    id,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created,
    description,
    name,
    hasResidentialInsurance AS has_residential_insurance,
    internalDisplayLabel AS internal_display_label,
    versionDisplayContract AS version_display_contract,
    isAuthWithAdminContract AS is_auth_with_admin_contract,
    shouldCalculateFirstPayment AS should_calculate_first_payment,
    isSelfCondo AS is_self_condo
FROM
    datalake_ebdb_raw.contractversion