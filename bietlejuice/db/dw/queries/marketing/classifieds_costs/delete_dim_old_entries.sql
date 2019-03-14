delete from marketing.dim_classified
where sk_classified in (
    select sk_classified
    from staging.dim_classified
)