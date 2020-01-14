drop table if exists gsheets.inside_sales_target;
create table gsheets.inside_sales_target
(
    "Canal" varchar(10) not null,
    "ID" varchar(255) not null,
    "Listing" varchar(255) not null,
    "Manager" varchar(16) not null,
    "Manager ID" varchar(255) not null,
    "Nome" varchar(33) not null,
    "Opportunity" varchar(255) not null,
    "TL" varchar(10) not null,
    "TL ID" varchar(255)
);
