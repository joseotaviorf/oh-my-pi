drop table public.dim_reservation;
CREATE TABLE public.dim_reservation(
sk_reservation bigint primary key,
id_reservation bigint,
ts_created timestamp,
ts_updated timestamp,
version int4,
attempt int4,
status varchar(255),
cancellation_reason varchar(255),
value decimal(19, 2),
is_ongoing int4,
installments int4
);
