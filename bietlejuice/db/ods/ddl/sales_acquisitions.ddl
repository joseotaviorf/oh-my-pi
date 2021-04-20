drop table public.sales_acquisitions;
create table public.sales_acquisitions (
    id bigint,
    flow varchar(255),
    acquisition_method varchar(255),
    acquisition_channel varchar(255),
    acquisition_source varchar(255),
    is_doorman bool
);