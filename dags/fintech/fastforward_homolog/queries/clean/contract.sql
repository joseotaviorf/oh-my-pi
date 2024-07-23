SELECT
    id,
    external_id as id_external,
    landlord_id as id_landlord,
    owner_id as id_owner,
    house_id as id_house,
    brokerage_fee_id as id_brokerage_fee,
    installment_plan_id as id_installment_plan,
    off_limits as is_off_limits,
    start_date as ts_started,
    created_at as ts_created,
    updated_at as ts_updated,
    end_date as ts_ended
FROM
    datalake_fastforward_homolog_raw.contract
