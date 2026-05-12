class MetadataFileInfo:
    def __init__(
        self,
        local_path=None,
        s3_path=None,
        database_name=None,
        table_name=None,
        has_lineage=None,
        has_tags=None,
        has_documentation=None,
        has_metric=None,
        layer=None,
        domain=None,
        dag=None,
    ):
        self.local_path = local_path
        self.s3_path = s3_path
        self.database_name = database_name
        self.table_name = table_name
        self.has_lineage = has_lineage
        self.has_tags = has_tags
        self.has_documentation = has_documentation
        self.has_metric = has_metric
        self.layer = layer
        self.domain = domain
        self.dag = dag
