SELECT
    id as id_contract,
    external_id as id_external,
    landlord_id as id_landlord,
    house_id as id_house,
    owner_id as id_owner,
    brokerage_fee_id as id_brokerage_fee,
    installment_plan_id as id_installment_plan,
    rev,
    revtype as rev_type,
    revend as rev_end,
    off_limits as is_off_limits,
    start_date as ts_started,
    end_date as ts_ended
FROM
    datalake_fastforward_homolog_raw.contract_aud
