SELECT
    id,
    app,
    name,
    timestamp(applied) as ts_applied
FROM datalake_chat_fup_raw.django_migrations