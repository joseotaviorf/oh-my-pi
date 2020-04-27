select
    id,
    atualizadoEm as ts_updated,
    criadoEm as ts_created,
    administrationSplitPercentage as administration_split_percentage,
    brokerageSplitPercentage as brokerage_split_percentage,
    contractPlan as contract_plan,
    contract_id as id_contract,
    partner_id as id_partner
from
    datalake_ebdb_raw.contractpartnershipdata