DROP TABLE IF EXISTS public.dim_agent_review;
CREATE TABLE public.dim_agent_review (
    sk_agentreview bigint NOT NULL,
    sk_booking bigint,
    rating integer,
    tag_other varchar(500),
    flg_punctuality integer,
    flg_agent_well_informed integer,
    flg_kindness integer,
    flg_no_kindness integer,
    flg_house_as_listing integer,
    flg_house_not_as_listing integer,
    flg_other_reason_positive integer,
    flg_other_reason_negative integer,
    flg_agent_late integer,
    flg_agent_with_no_info integer,
    dt_rating timestamp,
    dt_timestamp timestamp,
    CONSTRAINT dim_agent_review_pkey PRIMARY KEY(sk_agentreview)
)

ALTER TABLE public.dim_agent_review OWNER TO databricks;