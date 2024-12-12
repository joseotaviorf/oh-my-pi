SELECT
    action_code,
    action,
    result_code,
    result,
    complement_code,
    complement,
    esforco,
    alo,
    cpc,
    promessa,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.cyber_collection_actions
