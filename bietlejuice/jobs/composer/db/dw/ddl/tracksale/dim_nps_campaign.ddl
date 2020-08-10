drop table if exists tracksale.dim_nps_campaign;
create table if not exists tracksale.dim_nps_campaign (
    sk_nps_campaign bigint,
    name varchar(100),
    main_channel varchar(10),
    business_context varchar(20),
    customer_journey varchar(10),
    purpose varchar(20),
    customer_type varchar(30),
    partner_name varchar(30),
    metric_group varchar(30),
    ts_created timestamp,
    ts_load timestamp
)
