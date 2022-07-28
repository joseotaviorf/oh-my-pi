select
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    description,
    name,
    hasResidentialInsurance as has_residential_insurance,
    internalDisplayLabel as internal_display_label,
    versionDisplayContract as version_display_contract,
    isAuthWithAdminContract as is_auth_with_admin_contract,
    shouldCalculateFirstPayment as should_calculate_first_payment,
    isSelfCondo as is_self_condo
from
    datalake_ebdb_raw.contractversion