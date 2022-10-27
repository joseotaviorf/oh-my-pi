SELECT
    uuid as id,
    parentUUID as id_parent,
    code,
    context,
    duration,
    err as error_message,
    fail as has_failed,
    fullTitle as full_title,
    isHook as is_hook,
    pass as has_passed,
    pending as is_pending,
    skipped as has_been_skipped,
    speed,
    state,
    timedOut as has_timed_out,
    title,
    COALESCE(GET_JSON_OBJECT(context, '$.value'), 0) as retry_count,
    pwa,
    dt
FROM datalake_cypress_raw.tests
WHERE
     date(dt) = date('{year}-{month}-{day}')