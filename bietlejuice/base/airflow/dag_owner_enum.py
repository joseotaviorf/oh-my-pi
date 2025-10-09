class DAGOwnerEnum:
    """
    Mapping of all Analytics and Data Engineering teams for defining DAG owners.
    """

    DEFAULT_OWNER = "Data Engineering"
    DATA_3P_PARTNERS = "Data 3P Partners"
    DATA_AGENTS = "Data Agents"
    DATA_CONVERSATIONAL_XP = "Data Conversational XP"
    DATA_DS_PRICING = "Data DS Pricing"
    DATA_FINTECH = "Data Fintech"
    DATA_FOR_RENT = "Data ForRent"
    DATA_FOR_SALE = "Data ForSale"
    DATA_GOVERNANCE = "Data Governance"
    DATA_GROWTH = "Data Growth"
    DATA_PEOPLE = "Data People"
    DATA_LIFE_CYCLE = "Data Life Cycle"
    DATA_PRIMITIVES = "Data Primitives"
    DATA_SS = "Data SS"
    DATA_PP = "Data Planning & Performance"
    MLOPS = "MLOps"
    QCX = "QCX"
    TECH_PLATAFORM_CYBER_SECURITY = "Tech Platform Cyber Security"
    TECH_PLATAFORM_DEV_FOUNDATION = "Tech Platform Dev Foundation"
    TECH_PLATAFORM_WORKFORCE_PRODUCTIVITY = "Tech Platform Workforce Productivity"

    @classmethod
    def get_available_enum_values(cls):
        return [
            v
            for k, v in cls.__dict__.items()
            if not k.startswith("_") and isinstance(v, str)
        ]
