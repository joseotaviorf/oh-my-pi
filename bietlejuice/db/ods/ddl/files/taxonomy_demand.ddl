drop table if exists files.taxonomy_demand;
create table files.taxonomy_demand (
    app_type varchar(255),
    utm_source varchar(255),
    utm_medium varchar(255),
    branded varchar(255),
    first_update_source varchar(255),
    flg_via_reschedule integer,
    Category varchar(255),
    Flow varchar(255),
    Completion varchar(255),
    Channel varchar(255),
    Medium varchar(255),
    Source varchar(255),
    Platform varchar(255)
);