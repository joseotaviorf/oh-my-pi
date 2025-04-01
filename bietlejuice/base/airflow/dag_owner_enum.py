class DAGOwnerEnum:
    """
    Mapping of all Analytics and Data Engineering teams for defining DAG owners.
    """

    DEFAULT_OWNER = "Data Engineering"
    DATA_AGENTS = "Data Agents"
    DATA_AVAILABILITY = "Data Availability"
    DATA_BEDROCK = "Data Bedrock"
    DATA_CDP = "Data CDP"
    DATA_FINTECH = "Data Fintech"
    DATA_FOR_RENT = "Data ForRent"
    DATA_FOR_SALE = "Data ForSale"
    DATA_GOVERNANCE = "Data Governance"
    DATA_GROWTH = "Data Growth"
    DATA_INTERNATIONAL = "Data International"
    DATA_PEOPLE = "Data People"
    DATA_PLATFORM = "Data Platform"
    DATA_INGESTION = "Data Ingestion"
    DATA_PRIMITIVES = "Data Primitives"
    DATA_REDE = "Data Rede"
    DATA_SS = "Data SS"
    MLOPS = "MLOps"
    TECH_PLATAFORM_CYBER_SECURITY = "Tech Platform Cyber Security"
    TECH_PLATAFORM_DEV_FOUNDATION = "Tech Platform Dev Foundation"

    @classmethod
    def get_available_enum_values(cls):
        return [
            v
            for k, v in cls.__dict__.items()
            if not k.startswith("_") and isinstance(v, str)
        ]
