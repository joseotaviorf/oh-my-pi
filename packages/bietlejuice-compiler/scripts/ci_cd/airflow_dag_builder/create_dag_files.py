import argparse
from glob import glob
from os import makedirs, path, remove
from os.path import basename, dirname, exists, join, relpath

from bietlejuice.base.airflow.dag_builders.main_builder.dag_declaration.dag_yaml_parser import (
    load_cluster_file,
    resolve_validation_block,
)
from bietlejuice.base.airflow.datasets.dataset_encoder import DatasetEncoder
from bietlejuice.base.airflow.enums.criticality_enum import CriticalityEnum
from bietlejuice.base.dependencies.bietlejuice_dependency_helper import (
    BietlejuiceDependencyHelper,
)
from bietlejuice.base.dependencies.bietlejuice_redundant_dependency_finder import (
    BietlejuiceRedundantDependencyFinder,
)
from bietlejuice.services.dataset_service import DatasetService
from bietlejuice.services.file_service import FileService
from dags import DAG_PACKAGES_ROOT
from scripts import SCRIPTS_PATH

DAG_PYTHON_FILE_SUFFIX = "_dag"
VALIDATION_DAG_PYTHON_FILE_SUFFIX = "_validation_dag"
DAGS_TEMPLATE_FILE_PATH = join(
    SCRIPTS_PATH, "ci_cd/airflow_dag_builder/__dags_template__.py"
)
VALIDATION_DAGS_TEMPLATE_FILE_PATH = join(
    SCRIPTS_PATH, "ci_cd/airflow_dag_builder/__validation_dags_template__.py"
)
DOMAIN_BUNDLE_TEMPLATE_FILE_PATH = join(
    SCRIPTS_PATH, "ci_cd/airflow_dag_builder/__domain_bundle_template__.py"
)
PYTHON_BUNDLE_TEMPLATE_FILE_PATH = join(
    SCRIPTS_PATH, "ci_cd/airflow_dag_builder/__python_bundle_template__.py"
)
DEFAULT_BUNDLE_OUTPUT_DIR = join(DAG_PACKAGES_ROOT, "_astro_bundles")
DEFAULT_BUNDLE_EXCLUDE_FILE = join(
    dirname(DAG_PACKAGES_ROOT), "astro", "generated-dag-excludes.txt"
)
DEFAULT_MIGRATION_BUNDLE_GROUP = "platform_migration"
MIGRATION_DAG_KINDS = ("twin", "emr", "compare")
VALIDATION_BUNDLE_FILE_PREFIX = "_validation_bundle_"


def has_validation_cluster(dag_package_path: str, dag_name: str) -> bool:
    """Return whether the parser-resolved validation block defines a cluster."""
    declaration = FileService.get_dict_from_yaml_file(
        join(dag_package_path, f"{dag_name}_declaration.yml")
    )

    validation_from_cluster = None
    for ext in (".yml", ".yaml"):
        cluster_path = join(dag_package_path, f"{dag_name}_cluster{ext}")
        if exists(cluster_path):
            _, validation_from_cluster = load_cluster_file(cluster_path)
            break

    validation = resolve_validation_block(declaration, validation_from_cluster) or {}
    return isinstance(validation, dict) and bool(validation.get("cluster"))


def _read_declaration_dataset_dependencies(declaration_path: str) -> list[str] | None:
    """Return ``dag.dataset_dependencies`` from a declaration YAML, if present."""
    declaration = FileService.get_dict_from_yaml_file(declaration_path)
    dag_block = declaration.get("dag") or {}
    dataset_dependencies = dag_block.get("dataset_dependencies")
    if dataset_dependencies is None:
        return None
    if not isinstance(dataset_dependencies, list):
        raise ValueError(
            f"dataset_dependencies must be a list in {declaration_path}, "
            f"got {type(dataset_dependencies).__name__}"
        )
    if not dataset_dependencies:
        return None
    return dataset_dependencies


def _datasets_code(
    dag_name: str,
    dependencies: dict,
    redundant_dependency_finder: BietlejuiceRedundantDependencyFinder,
    declaration_path: str | None = None,
) -> str:
    dag_id = f"bietlejuice.{dag_name}"
    if dag_id in dependencies:
        dag_dependencies = dependencies[dag_id]
        redundant_dependencies = (
            redundant_dependency_finder.find_redundant_dependencies(dag_id)
        )
        datasets = DatasetService.get_dag_datasets_from_dependencies(
            dag_dependencies, redundant_dependencies
        )
        return DatasetEncoder.encode_dataset_as_python_code(datasets)

    declaration_dependencies = (
        _read_declaration_dataset_dependencies(declaration_path)
        if declaration_path
        else None
    )
    if declaration_dependencies:
        datasets = DatasetService.get_dag_datasets_from_dependencies(
            declaration_dependencies
        )
        return DatasetEncoder.encode_dataset_as_python_code(datasets)

    return DatasetEncoder.encode_dataset_as_python_code(None)


def _priority_tiers(dependencies: dict) -> dict[str, str]:
    """Each DAG's scheduling tier: the highest effective tier of itself and every DAG downstream of it."""
    own_tiers = {}
    for declaration_file in glob(
        f"{DAG_PACKAGES_ROOT}/**/*_declaration.yml", recursive=True
    ):
        declaration = FileService.get_dict_from_yaml_file(declaration_file) or {}
        own_tiers[basename(dirname(declaration_file))] = CriticalityEnum.effective_tier(
            declaration.get("dag") or {}, declaration.get("workflow") or {}
        )
    downstream_index = BietlejuiceDependencyHelper.build_downstream_index(dependencies)
    return {
        dag_name: CriticalityEnum.highest(
            [tier]
            + [
                own_tiers.get(downstream.removeprefix("bietlejuice."))
                for downstream in BietlejuiceDependencyHelper.find_downstream_dags(
                    f"bietlejuice.{dag_name}", downstream_index=downstream_index
                )
            ]
        )
        for dag_name, tier in own_tiers.items()
    }


def create_dag_files(
    dag_name_glob: str = "*",
    include_dir: str | None = None,
    exclude_dir: str | None = None,
) -> None:
    print("msg=Reading dependencies\n")
    dependencies = BietlejuiceDependencyHelper.read_dependencies()
    redundant_dependency_finder = BietlejuiceRedundantDependencyFinder(dependencies)
    priority_tiers = _priority_tiers(dependencies)

    print(f"template={DAGS_TEMPLATE_FILE_PATH}, msg=Creating DAG files from template\n")
    with open(DAGS_TEMPLATE_FILE_PATH) as f:
        template = f.read()
    with open(VALIDATION_DAGS_TEMPLATE_FILE_PATH) as f:
        validation_template = f.read()

    dag_files = glob(
        pathname=f"{DAG_PACKAGES_ROOT}/**/{dag_name_glob}_declaration.yml",
        recursive=True,
    )

    if include_dir:
        dag_files = [f for f in dag_files if f"/{include_dir}/" in f]
    if exclude_dir:
        dag_files = [f for f in dag_files if f"/{exclude_dir}/" not in f]

    for dag_file in dag_files:
        dag_package_path = dirname(dag_file)
        dag_name = basename(dag_package_path)
        dag_python_file = join(
            dag_package_path, f"{dag_name}{DAG_PYTHON_FILE_SUFFIX}.py"
        )
        validation_python_file = join(
            dag_package_path, f"{dag_name}{VALIDATION_DAG_PYTHON_FILE_SUFFIX}.py"
        )

        datasets_code = _datasets_code(
            dag_name, dependencies, redundant_dependency_finder, dag_file
        )

        with open(dag_python_file, "w") as f:
            f.write(
                template.format(
                    datasets=datasets_code, priority_tier=repr(priority_tiers[dag_name])
                )
            )
        print(
            f"dag_name={dag_name}, dag_python_file={dag_python_file}, msg=Created DAG python file\n"
        )

        if has_validation_cluster(dag_package_path, dag_name):
            with open(validation_python_file, "w") as f:
                f.write(validation_template)
            print(
                f"dag_name={dag_name}, dag_python_file={validation_python_file}, "
                "msg=Created validation DAG python file\n"
            )
        elif path.exists(validation_python_file):
            remove(validation_python_file)
            print(
                f"dag_name={dag_name}, dag_python_file={validation_python_file}, "
                "msg=Removed stale validation DAG python file\n"
            )


def _write_bundles(
    *,
    template: str,
    by_domain: dict[str, list[tuple[str, str, str]]],
    output_dir: str,
    file_prefix: str,
    max_dags_per_bundle: int,
    is_validation: bool,
) -> list[str]:
    """Write chunked bundle modules per domain, returning the generated paths."""
    generated_bundles = []
    for domain, specs in sorted(by_domain.items()):
        domain_output_dir = join(output_dir, domain)
        makedirs(domain_output_dir, exist_ok=True)
        for offset in range(0, len(specs), max_dags_per_bundle):
            chunk = specs[offset : offset + max_dags_per_bundle]
            bundle_number = offset // max_dags_per_bundle + 1
            bundle_path = join(
                domain_output_dir, f"{file_prefix}{bundle_number:02d}.py"
            )
            dag_specs = (
                "[\n"
                + "".join(
                    f"    ({dag_name!r}, {datasets_code}, {priority_tier_code}),\n"
                    for dag_name, datasets_code, priority_tier_code in chunk
                )
                + "]"
            )
            with open(bundle_path, "w") as f:
                f.write(
                    template.replace("__DAG_SPECS__", dag_specs).replace(
                        "__IS_VALIDATION__", repr(is_validation)
                    )
                )
            generated_bundles.append(bundle_path)
    return generated_bundles


def create_domain_bundles(
    *,
    max_dags_per_bundle: int = 25,
    exclude_dir: str | None = None,
    output_dir: str = DEFAULT_BUNDLE_OUTPUT_DIR,
    exclude_file: str = DEFAULT_BUNDLE_EXCLUDE_FILE,
    include_validation: bool = False,
) -> list[str]:
    """Generate deterministic domain bundles and an exact rsync exclude list.

    With *include_validation*, DAGs whose declaration resolves a
    ``validation.cluster`` also get ``_validation_bundle_NN.py`` modules. They are
    kept separate from the production bundles because a bundle module that fails to
    build any of its DAGs registers none of them — a broken validation twin must not
    take its production DAGs down with it. Only the prod pipeline asks for these.
    """
    if max_dags_per_bundle < 1:
        raise ValueError("max_dags_per_bundle must be at least 1")

    dependencies = BietlejuiceDependencyHelper.read_dependencies()
    redundant_dependency_finder = BietlejuiceRedundantDependencyFinder(dependencies)
    priority_tiers = _priority_tiers(dependencies)
    with open(DOMAIN_BUNDLE_TEMPLATE_FILE_PATH) as f:
        template = f.read()

    declaration_files = sorted(
        glob(f"{DAG_PACKAGES_ROOT}/**/*_declaration.yml", recursive=True)
    )
    if exclude_dir:
        declaration_files = [
            file_path
            for file_path in declaration_files
            if f"/{exclude_dir}/" not in file_path
        ]

    by_domain: dict[str, list[tuple[str, str, str]]] = {}
    validation_by_domain: dict[str, list[tuple[str, str, str]]] = {}
    excluded_stubs = []
    for declaration_file in declaration_files:
        dag_package_path = dirname(declaration_file)
        dag_name = basename(dag_package_path)
        domain = relpath(dag_package_path, DAG_PACKAGES_ROOT).split(path.sep, 1)[0]
        datasets_code = _datasets_code(
            dag_name, dependencies, redundant_dependency_finder, declaration_file
        )
        stub_path = join(dag_package_path, f"{dag_name}{DAG_PYTHON_FILE_SUFFIX}.py")
        excluded_stubs.append(relpath(stub_path, DAG_PACKAGES_ROOT))
        by_domain.setdefault(domain, []).append(
            (dag_name, datasets_code, repr(priority_tiers[dag_name]))
        )
        if include_validation and has_validation_cluster(dag_package_path, dag_name):
            # Validation DAGs never take dataset dependencies.
            validation_by_domain.setdefault(domain, []).append(
                (dag_name, "None", "None")
            )

    makedirs(output_dir, exist_ok=True)
    # Validation bundles are always cleaned, including when the flag is off, so a
    # forno/dev run never keeps prod-only bundles a previous run left behind.
    for pattern in ("_bundle_*.py", f"{VALIDATION_BUNDLE_FILE_PREFIX}*.py"):
        for stale_bundle in glob(join(output_dir, "**", pattern), recursive=True):
            remove(stale_bundle)

    generated_bundles = _write_bundles(
        template=template,
        by_domain=by_domain,
        output_dir=output_dir,
        file_prefix="_bundle_",
        max_dags_per_bundle=max_dags_per_bundle,
        is_validation=False,
    )

    makedirs(dirname(exclude_file), exist_ok=True)
    with open(exclude_file, "w") as f:
        f.write("\n".join(sorted(excluded_stubs)) + "\n")

    print(
        f"msg=Generated Astro domain bundles, bundles={len(generated_bundles)}, "
        f"dags={len(excluded_stubs)}, max_dags_per_bundle={max_dags_per_bundle}\n"
    )

    if include_validation:
        validation_bundles = _write_bundles(
            template=template,
            by_domain=validation_by_domain,
            output_dir=output_dir,
            file_prefix=VALIDATION_BUNDLE_FILE_PREFIX,
            max_dags_per_bundle=max_dags_per_bundle,
            is_validation=True,
        )
        validation_dags = sum(len(specs) for specs in validation_by_domain.values())
        print(
            f"msg=Generated Astro validation bundles, "
            f"bundles={len(validation_bundles)}, dags={validation_dags}, "
            f"max_dags_per_bundle={max_dags_per_bundle}\n"
        )
        generated_bundles += validation_bundles

    return generated_bundles


def _migration_kind_from_relpath(relpath: str) -> str | None:
    """Return twin/emr/compare when *relpath* is a platform migration DAG file."""
    # platform/migration_<kind>_<rest>/<file>_dag.py
    parts = relpath.split(path.sep)
    if len(parts) < 2 or parts[0] != "platform":
        return None
    folder = parts[1]
    for kind in MIGRATION_DAG_KINDS:
        prefix = f"migration_{kind}_"
        if folder.startswith(prefix):
            return kind
    return None


def create_python_dag_bundles(
    *,
    max_dags_per_bundle: int = 25,
    output_dir: str = DEFAULT_BUNDLE_OUTPUT_DIR,
    bundle_group: str = DEFAULT_MIGRATION_BUNDLE_GROUP,
) -> list[str]:
    """Generate exec-passthrough bundles for standalone migration Python DAGs.

    Unlike domain bundles (declaration rebuild), these modules ``exec`` the real
    ``*_dag.py`` sources so task callables and ``Path(__file__)`` lookups keep
    working. Per-DAG files must still ship in the Astro rsync payload; only
    ``.airflowignore`` stops the processor from parsing them individually.
    """
    if max_dags_per_bundle < 1:
        raise ValueError("max_dags_per_bundle must be at least 1")

    with open(PYTHON_BUNDLE_TEMPLATE_FILE_PATH) as f:
        template = f.read()

    by_kind: dict[str, list[str]] = {kind: [] for kind in MIGRATION_DAG_KINDS}
    for dag_file in sorted(glob(f"{DAG_PACKAGES_ROOT}/platform/migration_*/*_dag.py")):
        dag_relpath = relpath(dag_file, DAG_PACKAGES_ROOT)
        kind = _migration_kind_from_relpath(dag_relpath)
        if kind is None:
            continue
        by_kind[kind].append(dag_relpath)

    group_output_dir = join(output_dir, bundle_group)
    makedirs(group_output_dir, exist_ok=True)
    for stale_bundle in glob(join(group_output_dir, "_*_bundle_*.py")):
        remove(stale_bundle)

    generated_bundles = []
    total_dags = 0
    for kind in MIGRATION_DAG_KINDS:
        specs = by_kind[kind]
        total_dags += len(specs)
        for offset in range(0, len(specs), max_dags_per_bundle):
            chunk = specs[offset : offset + max_dags_per_bundle]
            bundle_number = offset // max_dags_per_bundle + 1
            bundle_path = join(
                group_output_dir, f"_{kind}_bundle_{bundle_number:02d}.py"
            )
            relpaths_code = "[\n" + "".join(f"    {rel!r},\n" for rel in chunk) + "]"
            with open(bundle_path, "w") as f:
                f.write(template.replace("__DAG_RELPATHS__", relpaths_code))
            generated_bundles.append(bundle_path)

    print(
        f"msg=Generated Astro Python migration bundles, "
        f"bundles={len(generated_bundles)}, dags={total_dags}, "
        f"max_dags_per_bundle={max_dags_per_bundle}\n"
    )
    return generated_bundles


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dag_name", "-d", required=False)
    parser.add_argument(
        "--include-dir",
        required=False,
        help="Build only declarations whose path is under dags/<DIR>/ (e.g. luigijr).",
    )
    parser.add_argument(
        "--exclude-dir",
        required=False,
        help="Skip declarations whose path is under dags/<DIR>/ (e.g. luigijr). Used by the "
        "normal pipeline to keep the luigijr sandbox out of the forno/prod DAG bag.",
    )
    parser.add_argument(
        "--bundle-domains",
        action="store_true",
        help="Generate Astro-only per-domain bundle modules instead of per-DAG stubs.",
    )
    parser.add_argument(
        "--bundle-migrations",
        action="store_true",
        help=(
            "Generate Astro-only exec-passthrough bundles for platform "
            "migration_{twin,emr,compare}_* Python DAGs."
        ),
    )
    parser.add_argument(
        "--include-validation",
        action="store_true",
        help=(
            "With --bundle-domains, also emit separate _validation_bundle_*.py modules "
            "for DAGs that resolve a validation.cluster. Production-only: forno and dev "
            "must not receive validation twin DAGs."
        ),
    )
    parser.add_argument(
        "--max-dags-per-bundle",
        type=int,
        default=25,
    )
    parser.add_argument("--bundle-output-dir", default=DEFAULT_BUNDLE_OUTPUT_DIR)
    parser.add_argument("--bundle-exclude-file", default=DEFAULT_BUNDLE_EXCLUDE_FILE)
    args = parser.parse_args(argv)
    ran_bundle = False
    if args.bundle_domains:
        create_domain_bundles(
            max_dags_per_bundle=args.max_dags_per_bundle,
            exclude_dir=args.exclude_dir,
            output_dir=args.bundle_output_dir,
            exclude_file=args.bundle_exclude_file,
            include_validation=args.include_validation,
        )
        ran_bundle = True
    if args.bundle_migrations:
        create_python_dag_bundles(
            max_dags_per_bundle=args.max_dags_per_bundle,
            output_dir=args.bundle_output_dir,
        )
        ran_bundle = True
    if not ran_bundle:
        create_dag_files(
            dag_name_glob=args.dag_name if args.dag_name else "*",
            include_dir=args.include_dir,
            exclude_dir=args.exclude_dir,
        )


if __name__ == "__main__":
    main()
