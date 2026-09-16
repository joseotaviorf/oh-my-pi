from enum import Enum


class LayerEnum(Enum):
    """Pipeline layers accepted in ``workflow.layer`` of a DAG declaration.

    Transitional state: the repo is moving toward a three-layer taxonomy
    (``ingestion`` -> ``transformation`` -> ``consumption``). ``INGESTION`` and
    ``TRANSFORMATION`` are the new vocabulary; every other member is the legacy
    vocabulary and both are accepted as siblings until the migration completes.
    This is deliberately an intermediate model, not the finished one — ``clean``,
    ``core`` and ``enrich`` are still top-level members rather than sub-layers of
    ``TRANSFORMATION``.

    Physical naming for the new members (see ``DatalakeMetastoreMapping``):

    - ``INGESTION``  -> ``datalake_{source}_transactional``, ``/transactional/{source}/``
    - ``TRANSFORMATION`` -> ``transformation_{source}``, ``/transformation/{source}/``

    ``TRANSFORMATION`` intentionally does **not** reuse the ``enrich`` naming
    (``datalake_{source}``). Source-layer policy classifies tables by schema name
    only (``layer_classifier.classify_schema_to_layer``), so sharing the enrich
    name would make the layer invisible to governance. The trade-off is that
    relabelling an existing enrich DAG is not a no-op; how that migration works —
    a legacy exception set versus classifying from the producing DAG's declared
    layer — is still open. No production DAG declares ``transformation`` yet, so
    this mapping can still be changed without moving data.

    ``INGESTION`` is vocabulary only until the CDC multi-layer design lands. It
    is a member so declarations can name it, but it is not a workflow layer:
    ``FactoryDispatcher`` has no factory for it, and it is excluded from the
    storage-format, Hive-descriptor, dataset-name, metadata-formula and
    metastore-factory registries — the same places ``TRANSACTIONAL`` (the
    physical store it aliases) is already absent, plus the ones a workflow
    layer would need. Declaring ``layer: ingestion`` fails at DAG build.

    Adding a member here is not enough on its own: it must also be registered in
    every layer-keyed map, or listed as an intentional absence.
    ``test_layer_registration_exhaustiveness`` enforces that and explains why.
    """

    TRANSACTIONAL = "transactional"
    RAW = "raw"
    CLEAN = "clean"
    CLEAN_STAGING = "clean_staging"
    CORE = "core"
    ENRICH = "enrich"
    DW_STAGING = "dw_staging"
    DW = "dw"
    METRIC = "metric"
    REVERSE = "reverse"
    QUBE = "qube"
    CONSUMPTION = "consumption"
    WONKA = "wonka"
    INGESTION = "ingestion"
    TRANSFORMATION = "transformation"

    @classmethod
    def get_available_enum_values(cls):
        return [member.value for member in cls]
