SELECT
    id,
    contract_id AS id_contract,
    partner_id AS id_partner,
    administrationSplitPercentage AS administration_split_percentage,
    brokerageSplitPercentage AS brokerage_split_percentage,
    contractPlan AS contract_plan,
    partnerType AS partner_type,
    tradeName AS trade_name,
    atualizadoEm AS ts_updated,
    criadoEm AS ts_created
FROM
    datalake_ebdb_raw.contractpartnershipdata