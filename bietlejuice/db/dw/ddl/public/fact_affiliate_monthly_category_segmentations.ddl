drop table public.fact_affiliate_monthly_category_segmentations;

create table if not exists public.fact_affiliate_monthly_category_segmentations (
    sk_date integer,
    sk_user_affiliate integer,
    sk_user integer,
    segmentation varchar(64),
    is_last_segmentation boolean
)