DROP TABLE staging.dim_reservation;

CREATE TABLE staging.dim_reservation(
sk_reservation bigint not null,
id bigint,
ts_created timestamp,
ts_updated timestamp,
version int4,
attempt int4,
status varchar(255),
value decimal(19, 2),
is_ongoing int4,
CONSTRAINT dim_reservation_pkey PRIMARY KEY(sk_reservation)
);