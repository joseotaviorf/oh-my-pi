drop table if exists quintoandar.dim_smart_price;
create table quintoandar.dim_smart_price (
    sk_smart_price bigint,
    id_smart_price bigint,
    is_enabled boolean,
    operation_mode varchar,
    status varchar,
    house_last_status varchar,
    house_min_rent integer,
    house_max_rent integer,
    min_rent_percentile integer,
    max_rent_percentile integer,
    offers_threshold integer,
    days_threshold integer,
    visits_days_threshold integer,
    ts_first_activation timestamp,
    ts_last_deactivation timestamp,
    ts_load timestamp
);