drop table if exists sauron.fact_session_tags;
create table if not exists sauron.fact_session_tags (
    sk_session bigint primary key,
    tag varchar(50)
)
