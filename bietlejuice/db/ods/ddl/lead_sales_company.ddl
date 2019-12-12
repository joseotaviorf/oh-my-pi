drop table if exists lead_sales_company;
create table lead_sales_company (
    id_lead integer,
    sales_company varchar(255),
    ts_sales_company_sent timestamp
);