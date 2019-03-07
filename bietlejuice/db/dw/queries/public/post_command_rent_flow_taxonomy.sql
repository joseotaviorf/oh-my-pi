UPDATE public.dim_rent_flow_taxonomy
    SET mkt_category = 'Not Mapped',
        mkt_flow = 'Not Mapped',
        mkt_completion = 'Not Mapped',
        mkt_channel = 'Not Mapped',
        mkt_medium = 'Not Mapped',
        mkt_source = 'Not Mapped',
        mkt_platform = 'Not Mapped'
WHERE sk_rent_flow_taxonomy = -1