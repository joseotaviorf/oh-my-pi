SELECT
    uuid as id,
    _timeout as timeout,
    afterHooks as after_hooks,
    beforeHooks as before_hooks,
    duration,
    failures,
    file,
    fullFile as full_file,
    passes,
    pending,
    root as is_root,
    rootEmpty as is_root_empty,
    skipped,
    title,
    pwa,
    dt
FROM datalake_cypress_raw.suites
WHERE
     date(dt) = date('{year}-{month}-{day}')