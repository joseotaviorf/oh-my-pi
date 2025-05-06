SELECT
    NULLIF(TRIM(action_code), "") AS action_code,
    action,
    NULLIF(TRIM(result_code), "") AS result_code,
    result,
    NULLIF(TRIM(complement_code), "") AS complement_code,
    complement,
    esforco,
    alo,
    cpc,
    promessa,
    NOW() AS ts_load
FROM
    datalake_gsheets_raw.cyber_collection_actions
