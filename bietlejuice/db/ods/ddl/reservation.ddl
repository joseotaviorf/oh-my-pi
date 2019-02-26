drop table if exists reservation;

create table reservation(
id bigint not null,
created_at timestamp not null,
updated_at timestamp not null,
version int not null,
attempt int not null,
rent_flow_id bigint default null,
status varchar(255),
tenant_id bigint default null,
value decimal(19, 2)default null,
house_id bigint default null,
mundipagg_token varchar(255)default null,
is_ongoing int default null,
CONSTRAINT reservation_pkey PRIMARY KEY(id)
);