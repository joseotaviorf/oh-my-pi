#!/usr/bin/env bash
# EMR / Databricks bootstrap for bietlejuice wheels from S3.
# EMR: pass artifacts bucket as $1 (see forno_conf.yml / prod_conf.yml init_scripts).
# Databricks: set PROVIDER=databricks; wheel S3 steps are skipped (install wheels via UI/CI if needed).

TMP_DIR="/tmp"

DEEQU_JAR_VERSION="${DEEQU_JAR_VERSION:-2.0.8}"
SPARK_VERSION="${SPARK_VERSION:-3.5}"
# Wheel metadata declares Requires-Python >=3.10; EMR default pip3 is 3.9 and installs with
# --ignore-requires-python (validated on EMR 7.12).
# Keep in lockstep with ClusterEnvVarsHelper.INMETRO_VERSION_MAP["3.5"]
# (yarn-env is not visible during EMR bootstrap; this default installs the wheel).
INMETRO_VERSION="${INMETRO_VERSION:-4.11.0}"
KAFKA_CLIENTS_JAR="${KAFKA_CLIENTS_JAR:-kafka-clients-3.5.1.jar}"
SPARK_SQL_KAFKA_JAR="${SPARK_SQL_KAFKA_JAR:-spark-sql-kafka-0-10_2.12-3.5.1.jar}"
SPARK_TOKEN_PROVIDER_KAFKA_JAR="${SPARK_TOKEN_PROVIDER_KAFKA_JAR:-spark-token-provider-kafka-0-10_2.12-3.5.1.jar}"
OPENLINEAGE_JAR="${OPENLINEAGE_JAR:-openlineage-spark_2.12-1.46.0.jar}"
MYSQL_JDBC_JAR="${MYSQL_JDBC_JAR:-mysql-connector-java-8.0.30.jar}"
# No hcatalog jar is bootstrapped: Glue JSON tables use the OpenX JsonSerDe,
# which EMR ships on the Spark classpath. hive-hcatalog-core was needed only
# while the catalog was on org.apache.hive.hcatalog.data.JsonSerDe (#27171).
QUINTOANDAR_LOGGER_WHEEL="${QUINTOANDAR_LOGGER_WHEEL:-quintoandar_logger-0.8.0-py3-none-any.whl}"
REQUESTS_VERSION="${REQUESTS_VERSION:-2.32.5}"
DATABRICKS_SDK_VERSION="${DATABRICKS_SDK_VERSION:-0.102.0}"
CLUSTER_YAML_LOCAL="${TMP_DIR}/emr_dag_cluster.yml"
CUSTOM_WHL_MANIFEST="${TMP_DIR}/emr_custom_whl_paths.txt"
CUSTOM_JAR_MANIFEST="${TMP_DIR}/emr_custom_jar_paths.txt"
EMR_CUSTOM_LIBRARIES_PY="${TMP_DIR}/emr_custom_libraries.py"
DAGS_S3_PREFIX="astronomer/dags/dags/"

# Normalize Airflow dag_id → DAG package folder name.
# bietlejuice.enrich_lost_listings → enrich_lost_listings
# bietlejuice.enrich_lost_listings__validation → enrich_lost_listings
_emr_normalize_dag_folder() {
    local dag_id="$1"
    local folder="${dag_id#bietlejuice.}"
    folder="${folder%__validation}"
    printf '%s' "${folder}"
}

# Resolve emr_custom_libraries.py for YAML parsing (sibling of this script locally,
# or download from artifacts bucket on EMR bootstrap).
# Must not write to stdout: extractors are invoked via command substitution
# (uris="$(…)") and awscli progress would be parsed as library URIs.
_emr_ensure_custom_libraries_py() {
    if [ -f "${EMR_CUSTOM_LIBRARIES_PY}" ]; then
        return 0
    fi

    local sibling
    sibling="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)/emr_custom_libraries.py"
    if [ -f "${sibling}" ]; then
        cp "${sibling}" "${EMR_CUSTOM_LIBRARIES_PY}"
        return 0
    fi

    if [ -z "${ARTIFACTS_BUCKET:-}" ]; then
        echo "Error: ARTIFACTS_BUCKET unset; cannot locate emr_custom_libraries.py" >&2
        return 1
    fi

    # Quiet progress: stdout would leak into uris="$( _emr_extract_* )" captures.
    if ! aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/emr_custom_libraries.py" \
        "${EMR_CUSTOM_LIBRARIES_PY}" >/dev/null; then
        echo "Error: failed to download emr_custom_libraries.py from ${ARTIFACTS_BUCKET}" >&2
        return 1
    fi
    return 0
}

# Download {dag}_cluster.yml (or _declaration.yml) from the Astronomer DAG bundle on S3.
# Runs early while EMR awscli is still reliable (later pip installs can break dateutil).
_emr_download_cluster_yaml() {
    local dag_folder="$1"
    local dest="$2"
    local bucket_name="${ARTIFACTS_BUCKET#s3://}"
    local domains
    local domain_prefix
    local suffix
    local key

    if [ -z "${dag_folder}" ]; then
        echo "  WARN: empty dag folder; skipping custom_libraries discovery"
        return 1
    fi

    echo "Discovering cluster YAML for dag_folder=${dag_folder} under s3://${bucket_name}/${DAGS_S3_PREFIX}"
    domains="$(
        aws s3api list-objects-v2 \
            --bucket "${bucket_name}" \
            --prefix "${DAGS_S3_PREFIX}" \
            --delimiter "/" \
            --query 'CommonPrefixes[].Prefix' \
            --output text 2>/dev/null || true
    )"
    if [ -z "${domains}" ]; then
        echo "  WARN: no domain prefixes under ${DAGS_S3_PREFIX}; skipping custom_libraries"
        return 1
    fi

    for suffix in "_cluster.yml" "_declaration.yml"; do
        for domain_prefix in ${domains}; do
            key="${domain_prefix}${dag_folder}/${dag_folder}${suffix}"
            if aws s3api head-object --bucket "${bucket_name}" --key "${key}" >/dev/null 2>&1; then
                echo "  Found s3://${bucket_name}/${key}"
                if aws s3 cp "s3://${bucket_name}/${key}" "${dest}"; then
                    return 0
                fi
                echo "  WARN: failed to download s3://${bucket_name}/${key}"
                return 1
            fi
        done
    done

    echo "  WARN: no ${dag_folder}_cluster.yml / _declaration.yml under ${DAGS_S3_PREFIX}; skipping custom_libraries"
    return 1
}

# Parse custom_libraries pypi entries from a cluster/declaration YAML.
# Prints TSV lines: package<TAB>no_deps(0|1)<TAB>only_binary(0|1)<TAB>ignore_installed(0|1).
# Always reads cluster.custom_libraries; when is_validation=1 also unions
# validation.cluster.custom_libraries. Optional EMR-only flags under pypi:
#   no_deps: true            → pip --no-deps
#   only_binary: true         → pip --only-binary=:all:
#   ignore_installed: true    → pip --ignore-installed (RPM overlay packages)
_emr_extract_pypi_packages() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    _emr_ensure_custom_libraries_py || return 1
    python3 "${EMR_CUSTOM_LIBRARIES_PY}" pypi "${cluster_yaml}" "${is_validation}"
}

# Install DAG-level custom_libraries PyPI packages (Databricks parity on EMR).
_emr_install_custom_pypi_libraries() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    local packages
    local pkg
    local no_deps
    local only_binary
    local -a pip_flags

    echo "BEGIN: Install custom_libraries PyPI packages from cluster YAML"

    if [ ! -f "${cluster_yaml}" ]; then
        echo "  WARN: cluster YAML not present at ${cluster_yaml}; skipping"
        echo "END: Install custom_libraries PyPI packages (skipped)"
        return 0
    fi

    if ! packages="$(_emr_extract_pypi_packages "${cluster_yaml}" "${is_validation}")"; then
        echo "Error: failed to parse custom_libraries from ${cluster_yaml}"
        exit 1
    fi

    if [ -z "${packages}" ]; then
        echo "  No pypi entries in custom_libraries; nothing to install"
        echo "END: Install custom_libraries PyPI packages (none)"
        return 0
    fi

    echo "  Packages to install:"
    while IFS=$'\t' read -r pkg no_deps only_binary ignore_installed; do
        [ -z "${pkg}" ] && continue
        echo "    ${pkg} (no_deps=${no_deps:-0} only_binary=${only_binary:-0} ignore_installed=${ignore_installed:-0})"
    done <<EOF
${packages}
EOF

    while IFS=$'\t' read -r pkg no_deps only_binary ignore_installed; do
        [ -z "${pkg}" ] && continue
        pip_flags=(--no-cache-dir)
        if [ "${no_deps:-0}" = "1" ]; then
            pip_flags+=(--no-deps)
        else
            pip_flags+=(-c "${EMR_CONSTRAINTS}")
        fi
        if [ "${only_binary:-0}" = "1" ]; then
            pip_flags+=(--only-binary=:all:)
        fi
        if [ "${ignore_installed:-0}" = "1" ]; then
            pip_flags+=(--ignore-installed)
        fi
        echo "  Installing ${pkg}..."
        _emr_pip_install install "${pip_flags[@]}" "${pkg}"
    done <<EOF
${packages}
EOF

    echo "END: Install custom_libraries PyPI packages"
}

# Install system gnupg2 / gpg-agent so OIC PIN raw jobs can decrypt PGP payloads.
# Databricks Runtime images already ship gpg-agent; EMR Amazon Linux 2023 ships
# gnupg2-minimal (gpg without gpg-agent). Full gnupg2 conflicts with that package,
# so install must use --allowerasing to replace it. Retry on RPM lock races that
# happen when EMR bootstrap overlaps another package transaction on the node.
_emr_install_system_gnupg() {
    echo "BEGIN: Install gnupg2 / gpg-agent (PGP decrypt for OIC/PIN DAGs)"

    if command -v gpg >/dev/null 2>&1 && command -v gpg-agent >/dev/null 2>&1; then
        echo "  gpg already present: $(command -v gpg)"
        echo "  gpg-agent already present: $(command -v gpg-agent)"
        echo "END: Install gnupg2 / gpg-agent (already present)"
        return 0
    fi

    local attempt
    local max_attempts=8
    local sleep_secs=15
    local install_ok=0

    for attempt in $(seq 1 "${max_attempts}"); do
        echo "  attempt ${attempt}/${max_attempts}: install gnupg2 (replace gnupg2-minimal)"
        if command -v dnf >/dev/null 2>&1; then
            if sudo dnf install -y --allowerasing gnupg2; then
                install_ok=1
                break
            fi
        elif command -v yum >/dev/null 2>&1; then
            if sudo yum install -y --allowerasing gnupg2; then
                install_ok=1
                break
            fi
        else
            echo "Error: neither dnf nor yum is available to install gnupg2."
            exit 1
        fi
        echo "  WARN: package install failed (often RPM lock). Retrying in ${sleep_secs}s..."
        sleep "${sleep_secs}"
    done

    if [ "${install_ok}" -ne 1 ]; then
        echo "Error: gnupg2 install failed after ${max_attempts} attempts."
        exit 1
    fi

    if ! command -v gpg >/dev/null 2>&1; then
        echo "Error: gpg binary still missing after gnupg2 install."
        exit 1
    fi
    if ! command -v gpg-agent >/dev/null 2>&1; then
        echo "Error: gpg-agent binary still missing after gnupg2 install."
        exit 1
    fi

    echo "  gpg: $(command -v gpg)"
    echo "  gpg-agent: $(command -v gpg-agent)"
    echo "END: Install gnupg2 / gpg-agent"
}

# Retry pip (PyPI ConnectionResetError / OSError) then abort bootstrap.
# Uses $PIP_EXEC at call time (sudo pip3 on EMR, Databricks pip on DBR).
_emr_pip_install() {
    local max_attempts="${EMR_PIP_MAX_ATTEMPTS:-5}"
    local sleep_secs="${EMR_PIP_RETRY_SLEEP_SECS:-15}"
    local attempt
    local -a pip_args=("$@")

    if [ -z "${PIP_EXEC:-}" ]; then
        echo "Error: PIP_EXEC is unset; cannot run pip."
        exit 1
    fi
    if [ "${#pip_args[@]}" -eq 0 ]; then
        echo "Error: _emr_pip_install requires pip arguments (e.g. install ...)."
        exit 1
    fi

    if [ "${pip_args[0]}" = "install" ]; then
        pip_args=(install --retries 5 --timeout 30 "${pip_args[@]:1}")
    fi

    for attempt in $(seq 1 "${max_attempts}"); do
        echo "  pip attempt ${attempt}/${max_attempts}: ${PIP_EXEC} ${pip_args[*]}"
        if $PIP_EXEC "${pip_args[@]}"; then
            return 0
        fi
        if [ "${attempt}" -eq "${max_attempts}" ]; then
            break
        fi
        echo "  WARN: pip failed (attempt ${attempt}/${max_attempts}). Retrying in ${sleep_secs}s..."
        sleep "${sleep_secs}"
    done
    echo "Error: pip failed after ${max_attempts} attempts: ${PIP_EXEC} ${pip_args[*]}"
    exit 1
}

# Parse custom_libraries whl entries from a cluster/declaration YAML.
# Prints one URI string per line (may contain {artifacts_bucket}). Always reads
# cluster.custom_libraries; when is_validation=1 also unions
# validation.cluster.custom_libraries.
_emr_extract_whl_uris() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    _emr_ensure_custom_libraries_py || return 1
    python3 "${EMR_CUSTOM_LIBRARIES_PY}" whl "${cluster_yaml}" "${is_validation}"
}

# Parse custom_libraries jar entries from a cluster/declaration YAML.
# Prints one URI string per line (may contain {artifacts_bucket}). Always reads
# cluster.custom_libraries; when is_validation=1 also unions
# validation.cluster.custom_libraries.
_emr_extract_jar_uris() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    _emr_ensure_custom_libraries_py || return 1
    python3 "${EMR_CUSTOM_LIBRARIES_PY}" jar "${cluster_yaml}" "${is_validation}"
}

# Parse custom_libraries maven entries. Prints TSV:
# coordinates<TAB>repo_or_empty<TAB>relative_path<TAB>jar_name
_emr_extract_maven_coords() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    _emr_ensure_custom_libraries_py || return 1
    python3 "${EMR_CUSTOM_LIBRARIES_PY}" maven "${cluster_yaml}" "${is_validation}"
}

# Resolve {artifacts_bucket} / accept s3:// URIs; download custom whls early
# (awscli still intact) and write local paths to CUSTOM_WHL_MANIFEST.
_emr_download_custom_whl_libraries() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    local uris
    local uri
    local resolved
    local basename
    local local_path

    echo "BEGIN: Download custom_libraries whl from cluster YAML"

    rm -f "${CUSTOM_WHL_MANIFEST}"

    if [ ! -f "${cluster_yaml}" ]; then
        echo "  WARN: cluster YAML not present at ${cluster_yaml}; skipping"
        echo "END: Download custom_libraries whl (skipped)"
        return 0
    fi

    if ! uris="$(_emr_extract_whl_uris "${cluster_yaml}" "${is_validation}")"; then
        echo "Error: failed to parse custom_libraries whl from ${cluster_yaml}"
        exit 1
    fi

    if [ -z "${uris}" ]; then
        echo "  No whl entries in custom_libraries; nothing to download"
        echo "END: Download custom_libraries whl (none)"
        return 0
    fi

    : >"${CUSTOM_WHL_MANIFEST}"

    while IFS= read -r uri; do
        [ -z "${uri}" ] && continue
        resolved="${uri//\{artifacts_bucket\}/${ARTIFACTS_BUCKET}}"
        case "${resolved}" in
            s3://*)
                ;;
            *)
                echo "Error: custom_libraries whl must resolve to an s3:// URI (got: ${resolved})"
                echo "  Original: ${uri}"
                exit 1
                ;;
        esac
        basename="$(basename "${resolved}")"
        local_path="${TMP_DIR}/wheels/${basename}"
        echo "  Downloading ${resolved} -> ${local_path}"
        if ! aws s3 cp "${resolved}" "${local_path}"; then
            echo "Error: aws s3 cp of custom_libraries whl '${resolved}' failed."
            exit 1
        fi
        printf '%s\n' "${local_path}" >>"${CUSTOM_WHL_MANIFEST}"
    done <<EOF
${uris}
EOF

    echo "END: Download custom_libraries whl"
}

# Resolve {artifacts_bucket} / accept s3:// URIs; download custom jars early
# (awscli still intact) and write local paths to CUSTOM_JAR_MANIFEST.
_emr_download_custom_jar_libraries() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    local uris
    local uri
    local resolved
    local basename
    local local_path

    echo "BEGIN: Download custom_libraries jar from cluster YAML"

    rm -f "${CUSTOM_JAR_MANIFEST}"

    if [ ! -f "${cluster_yaml}" ]; then
        echo "  WARN: cluster YAML not present at ${cluster_yaml}; skipping"
        echo "END: Download custom_libraries jar (skipped)"
        return 0
    fi

    if ! uris="$(_emr_extract_jar_uris "${cluster_yaml}" "${is_validation}")"; then
        echo "Error: failed to parse custom_libraries jar from ${cluster_yaml}"
        exit 1
    fi

    if [ -z "${uris}" ]; then
        echo "  No jar entries in custom_libraries; nothing to download"
        echo "END: Download custom_libraries jar (none)"
        return 0
    fi

    mkdir -p "${TMP_DIR}/jars"
    : >"${CUSTOM_JAR_MANIFEST}"

    while IFS= read -r uri; do
        [ -z "${uri}" ] && continue
        resolved="${uri//\{artifacts_bucket\}/${ARTIFACTS_BUCKET}}"
        case "${resolved}" in
            s3://*)
                ;;
            *)
                echo "Error: custom_libraries jar must resolve to an s3:// URI (got: ${resolved})"
                echo "  Original: ${uri}"
                exit 1
                ;;
        esac
        basename="$(basename "${resolved}")"
        local_path="${TMP_DIR}/jars/${basename}"
        echo "  Downloading ${resolved} -> ${local_path}"
        if ! aws s3 cp "${resolved}" "${local_path}"; then
            echo "Error: aws s3 cp of custom_libraries jar '${resolved}' failed."
            exit 1
        fi
        printf '%s\n' "${local_path}" >>"${CUSTOM_JAR_MANIFEST}"
    done <<EOF
${uris}
EOF

    echo "END: Download custom_libraries jar"
}

# Resolve maven:coordinates to JARs (S3 artifacts cache first, then Maven Central
# or optional repo URL). Appends local paths to CUSTOM_JAR_MANIFEST so install
# reuses _emr_install_custom_jar_libraries. Call after _emr_download_custom_jar_libraries
# (that function clears the manifest). Direct artifact only — no transitive Ivy resolve.
_emr_download_custom_maven_libraries() {
    local cluster_yaml="$1"
    local is_validation="${2:-0}"
    local rows
    local coordinates
    local repo
    local relative
    local jar_name
    local s3_uri
    local maven_url
    local local_path
    local repo_base

    echo "BEGIN: Download custom_libraries maven from cluster YAML"

    if [ ! -f "${cluster_yaml}" ]; then
        echo "  WARN: cluster YAML not present at ${cluster_yaml}; skipping"
        echo "END: Download custom_libraries maven (skipped)"
        return 0
    fi

    if ! rows="$(_emr_extract_maven_coords "${cluster_yaml}" "${is_validation}")"; then
        echo "Error: failed to parse custom_libraries maven from ${cluster_yaml}"
        exit 1
    fi

    if [ -z "${rows}" ]; then
        echo "  No maven entries in custom_libraries; nothing to download"
        echo "END: Download custom_libraries maven (none)"
        return 0
    fi

    mkdir -p "${TMP_DIR}/jars"
    touch "${CUSTOM_JAR_MANIFEST}"

    while IFS=$'\t' read -r coordinates repo relative jar_name; do
        [ -z "${coordinates}" ] && continue
        [ -z "${relative}" ] && continue
        [ -z "${jar_name}" ] && continue
        local_path="${TMP_DIR}/jars/${jar_name}"
        s3_uri="${ARTIFACTS_BUCKET}/jars/maven/${relative}"
        # "-" is the empty-repo sentinel from emr_custom_libraries.py (avoids bash
        # read collapsing consecutive tabs when repo is blank).
        if [ -z "${repo}" ] || [ "${repo}" = "-" ]; then
            repo_base="https://repo1.maven.org/maven2"
        else
            repo_base="${repo}"
        fi
        repo_base="${repo_base%/}"
        maven_url="${repo_base}/${relative}"

        echo "  Resolving ${coordinates}"
        if aws s3 cp "${s3_uri}" "${local_path}" 2>/dev/null; then
            echo "    from S3 cache ${s3_uri}"
        else
            echo "    S3 miss; fetching ${maven_url}"
            if ! curl -fsSL "${maven_url}" -o "${local_path}"; then
                echo "Error: failed to download maven artifact '${coordinates}'"
                echo "  Tried S3: ${s3_uri}"
                echo "  Tried URL: ${maven_url}"
                exit 1
            fi
        fi
        printf '%s\n' "${local_path}" >>"${CUSTOM_JAR_MANIFEST}"
    done <<EOF
${rows}
EOF

    echo "END: Download custom_libraries maven"
}

# Install Requires-Dist from a downloaded custom wheel under EMR_CONSTRAINTS.
# Keeps ``pip install --no-deps`` on the wheel itself (avoid upgrading EMR/PySpark)
# while restoring Databricks libraries-API parity for client/model wheels that
# omit explicit pypi: entries in *_cluster.yml.
# --ignore-requires-python: EMR bootstrap pip is 3.9; transitive deps may declare >=3.10.
_emr_install_whl_requires_dist() {
    local local_whl="$1"
    local reqs
    local req
    local -a uniq_reqs=()

    _emr_ensure_custom_libraries_py || return 1

    if [ -z "${EMR_CONSTRAINTS:-}" ] || [ ! -f "${EMR_CONSTRAINTS}" ]; then
        echo "Error: EMR_CONSTRAINTS unset/missing; cannot install wheel Requires-Dist"
        return 1
    fi

    if ! reqs="$(python3 "${EMR_CUSTOM_LIBRARIES_PY}" requires-dist "${local_whl}" "${EMR_CONSTRAINTS}")"; then
        echo "Error: failed to parse Requires-Dist from ${local_whl}"
        return 1
    fi

    while IFS= read -r req; do
        [ -z "${req}" ] && continue
        uniq_reqs+=("${req}")
    done <<EOF
${reqs}
EOF

    if [ "${#uniq_reqs[@]}" -eq 0 ]; then
        echo "    No Requires-Dist entries"
        return 0
    fi

    echo "    Installing Requires-Dist under constraints:"
    for req in "${uniq_reqs[@]}"; do
        echo "      ${req}"
    done
    _emr_pip_install install --no-cache-dir --ignore-requires-python -c "${EMR_CONSTRAINTS}" "${uniq_reqs[@]}"
}

# Install DAG-level custom_libraries wheels previously downloaded to CUSTOM_WHL_MANIFEST.
# Requires-Dist is installed first under EMR_CONSTRAINTS; the wheel itself uses
# --no-deps (avoid upgrading EMR/PySpark). Explicit pypi: entries in YAML still
# install earlier via _emr_install_custom_pypi_libraries.
# --ignore-requires-python: same as inmetro on EMR 3.9.
_emr_install_custom_whl_libraries() {
    local local_whl

    echo "BEGIN: Install custom_libraries whl from cluster YAML"

    if [ ! -f "${CUSTOM_WHL_MANIFEST}" ]; then
        echo "  No custom whl manifest; nothing to install"
        echo "END: Install custom_libraries whl (none)"
        return 0
    fi

    while IFS= read -r local_whl; do
        [ -z "${local_whl}" ] && continue
        if [ ! -f "${local_whl}" ]; then
            echo "Error: custom_libraries whl not found at ${local_whl}"
            exit 1
        fi
        echo "  Preparing deps for ${local_whl}..."
        if ! _emr_install_whl_requires_dist "${local_whl}"; then
            echo "Error: failed to install Requires-Dist for custom_libraries whl '${local_whl}'"
            exit 1
        fi
        echo "  Installing ${local_whl} (--no-deps)..."
        _emr_pip_install install --no-cache-dir --no-deps --ignore-requires-python "${local_whl}"
    done <"${CUSTOM_WHL_MANIFEST}"

    echo "END: Install custom_libraries whl"
}

# Spark Packages such as GraphFrames ship Python modules inside the same JAR as
# the JVM classes. Databricks Libraries / spark --packages put those on the
# Python path; copying the JAR into /usr/lib/spark/jars alone does not. Extract
# top-level packages (dir/__init__.py) into site-packages so `import graphframes`
# works on EMR.
_emr_extract_python_packages_from_jar() {
    local jar="$1"
    local site_packages
    local pkg
    local pkgs

    site_packages="$(python3 -c 'import site; print(site.getsitepackages()[0])')"
    pkgs="$(
        jar tf "${jar}" \
            | awk -F/ '$0 ~ /^[A-Za-z_][A-Za-z0-9_]*\/__init__\.py$/ { print $1 }' \
            | sort -u
    )"
    [ -z "${pkgs}" ] && return 0

    echo "  Extracting Python packages from $(basename "${jar}") → ${site_packages}"
    for pkg in ${pkgs}; do
        case "${pkg}" in
            META-INF|org|com|scala|java|javax|docs|test|tests) continue ;;
        esac
        echo "    ${pkg}/"
        # jar xf needs cwd=destination; keep absolute jar path.
        (cd "${site_packages}" && sudo jar xf "${jar}" "${pkg}/")
    done
}

# Install DAG-level custom_libraries jars previously downloaded to CUSTOM_JAR_MANIFEST
# into every Spark jars directory (Databricks libraries API parity on EMR).
_emr_install_custom_jar_libraries() {
    local local_jar
    local basename
    local jdir

    echo "BEGIN: Install custom_libraries jar into Spark classpath"

    if [ ! -f "${CUSTOM_JAR_MANIFEST}" ]; then
        echo "  No custom jar manifest; nothing to install"
        echo "END: Install custom_libraries jar (none)"
        return 0
    fi

    if [ -z "${SPARK_JARS_DIRS:-}" ]; then
        echo "Error: SPARK_JARS_DIRS unset; cannot install custom_libraries jar"
        exit 1
    fi

    while IFS= read -r local_jar; do
        [ -z "${local_jar}" ] && continue
        if [ ! -f "${local_jar}" ]; then
            echo "Error: custom_libraries jar not found at ${local_jar}"
            exit 1
        fi
        basename="$(basename "${local_jar}")"
        for jdir in ${SPARK_JARS_DIRS}; do
            sudo mkdir -p "${jdir}"
            sudo cp "${local_jar}" "${jdir}/${basename}"
            sudo chmod 644 "${jdir}/${basename}"
        done
        echo "  Installed ${basename}"
        _emr_extract_python_packages_from_jar "${local_jar}"
    done <"${CUSTOM_JAR_MANIFEST}"

    echo "END: Install custom_libraries jar"
}

echo "BEGIN: Install QuintoAndar internal libs"

if [ "${PROVIDER:-}" = "databricks" ]; then
    echo "PROVIDER=databricks. Using Databricks environment."
    PIP_EXEC="/databricks/python/bin/pip"
    echo "Installing awscli..."
    _emr_pip_install install -q awscli
else
    echo "Using EMR environment."

    if [ $# -lt 1 ]; then
        echo "Error: This script requires at least 1 argument."
        echo "Usage: $0 <artifacts_bucket> [databricks_s3_bucket] [airflow_dag_id]"
        exit 1
    fi

    ARTIFACTS_BUCKET="$1"
    DATABRICKS_S3_BUCKET="${2:-${DATABRICKS_S3_BUCKET:-}}"
    AIRFLOW_DAG_ID="${3:-${AIRFLOW_DAG_ID:-}}"
    PIP_EXEC="sudo pip3"
    echo "Skipping awscli installation (assumed pre-installed on EMR)."

    # Before wheel downloads / pip: PIN OIC raw decrypt needs gpg-agent on the node.
    _emr_install_system_gnupg

    if [ -n "$DATABRICKS_S3_BUCKET" ] && [ -n "$AIRFLOW_DAG_ID" ]; then
        echo "BEGIN: Create Spark event-log directory"
        aws s3api put-object \
            --bucket "$DATABRICKS_S3_BUCKET" \
            --key "spark-event-logs-emr/${AIRFLOW_DAG_ID}/" \
            || echo "  WARN: failed to create Spark event-log prefix"
        echo "END: Create Spark event-log directory"
    fi

    # Fetch cluster YAML early (awscli still intact) for later custom_libraries install.
    EMR_IS_VALIDATION=0
    case "${AIRFLOW_DAG_ID}" in
        *__validation) EMR_IS_VALIDATION=1 ;;
    esac
    if [ "${SKIP_CUSTOM_LIBRARIES:-0}" = "1" ]; then
        echo "SKIP_CUSTOM_LIBRARIES=1; skipping DAG cluster YAML discovery"
        rm -f "${CLUSTER_YAML_LOCAL}" "${CUSTOM_WHL_MANIFEST}" "${CUSTOM_JAR_MANIFEST}"
    elif [ -n "${AIRFLOW_DAG_ID}" ]; then
        echo "BEGIN: Download DAG cluster YAML for custom_libraries"
        EMR_DAG_FOLDER="$(_emr_normalize_dag_folder "${AIRFLOW_DAG_ID}")"
        echo "  airflow_dag_id=${AIRFLOW_DAG_ID} dag_folder=${EMR_DAG_FOLDER} is_validation=${EMR_IS_VALIDATION}"
        # Fetch the YAML parser before any uris="$( _emr_extract_* )" so awscli
        # progress cannot leak into library URI captures.
        _emr_ensure_custom_libraries_py \
            || echo "  WARN: emr_custom_libraries.py unavailable; custom_libraries parse may fail"
        _emr_download_cluster_yaml "${EMR_DAG_FOLDER}" "${CLUSTER_YAML_LOCAL}" \
            || rm -f "${CLUSTER_YAML_LOCAL}"
        echo "END: Download DAG cluster YAML for custom_libraries"
    else
        # Drop any leftover from a prior bootstrap on this host so install cannot
        # pick up another DAG's custom_libraries via the fixed CLUSTER_YAML_LOCAL path.
        echo "WARN: AIRFLOW_DAG_ID not set; skipping custom_libraries discovery"
        rm -f "${CLUSTER_YAML_LOCAL}" "${CUSTOM_WHL_MANIFEST}" "${CUSTOM_JAR_MANIFEST}"
    fi
fi

# --- Wheel download (EMR only; Databricks uses cluster libraries / other path) ---
if [ "${PROVIDER:-}" != "databricks" ]; then
    echo "Downloading libraries from S3 into ${TMP_DIR}..."
    sudo mkdir -p "${TMP_DIR}/wheels"
    sudo chown "$(whoami)" "${TMP_DIR}/wheels"

    aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/bietlejuice_core-latest-py3-none-any.whl" \
        "${TMP_DIR}/wheels/bietlejuice_core-latest-py3-none-any.whl"
    aws s3 cp "${ARTIFACTS_BUCKET}/bi-etl-ejuice/bietlejuice_runtime-latest-py3-none-any.whl" \
        "${TMP_DIR}/wheels/bietlejuice_runtime-latest-py3-none-any.whl"
    aws s3 cp "${ARTIFACTS_BUCKET}/python-logger/${QUINTOANDAR_LOGGER_WHEEL}" \
        "${TMP_DIR}/wheels/${QUINTOANDAR_LOGGER_WHEEL}"
    aws s3 cp "${ARTIFACTS_BUCKET}/inmetro/inmetro-${INMETRO_VERSION}-py3-none-any.whl" \
        "${TMP_DIR}/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl"

    # Custom whl/jar/maven downloads while awscli is still reliable (before heavy pip).
    if [ "${SKIP_CUSTOM_LIBRARIES:-0}" = "1" ]; then
        echo "SKIP_CUSTOM_LIBRARIES=1; skipping custom_libraries whl/jar/maven download"
        rm -f "${CUSTOM_WHL_MANIFEST}" "${CUSTOM_JAR_MANIFEST}"
    elif [ -n "${AIRFLOW_DAG_ID:-}" ]; then
        _emr_download_custom_whl_libraries "${CLUSTER_YAML_LOCAL}" "${EMR_IS_VALIDATION:-0}"
        _emr_download_custom_jar_libraries "${CLUSTER_YAML_LOCAL}" "${EMR_IS_VALIDATION:-0}"
        _emr_download_custom_maven_libraries "${CLUSTER_YAML_LOCAL}" "${EMR_IS_VALIDATION:-0}"
    else
        rm -f "${CUSTOM_WHL_MANIFEST}" "${CUSTOM_JAR_MANIFEST}"
    fi

    # Pin urllib3 / requests for awscli before resolving the big stack.
    _emr_pip_install install --upgrade --ignore-installed \
        "requests==${REQUESTS_VERSION}" 'urllib3>=1.25.4,<1.27'

    echo "Installing quintoandar-logger wheel (with deps)..."
    _emr_pip_install install --no-cache-dir "${TMP_DIR}/wheels/${QUINTOANDAR_LOGGER_WHEEL}"

    # Mirrors packages/bietlejuice-runtime [tool.uv].override-dependencies for pip (constraints
    # only narrow the solver; they cannot relax validations-engine's requests==2.28.1 pin).
    # urllib3 is capped for EMR awscli/botocore — all -c "${EMR_CONSTRAINTS}" installs
    # (bietlejuice deps, custom_libraries pypi, wheel Requires-Dist) must not upgrade it.
    EMR_CONSTRAINTS="${TMP_DIR}/emr-pip-constraints.txt"
    cat >"${EMR_CONSTRAINTS}" <<'EOF'
requests>=2.32.3
tenacity>=8.0.1
urllib3>=1.25.4,<1.27
EOF

    # validations-engine 2.0.0 declares requests==2.28.1; bietlejuice-core needs >=2.32.3.
    # Install it without deps after pinning requests (same effect as uv override-dependencies).
    echo "Installing validations-engine (no-deps; requests already pinned)..."
    _emr_pip_install install --no-cache-dir --no-deps 'validations-engine==2.0.0'

    # PyPI deps from bietlejuice-runtime + bietlejuice-core wheels (excluding validations-engine,
    # which is already installed). Keeps one resolver pass under constraints.
    echo "Installing bietlejuice transitive PyPI dependencies (constraints)..."
    _emr_pip_install install --no-cache-dir -c "${EMR_CONSTRAINTS}" \
        'bs4>=0.0.1' \
        'boto3>=1.37.3' \
        'businesstimedelta' \
        'Cerberus>=1.3.5' \
        'dependency-injector>=4.46.0' \
        'Deprecated>=1.2.18' \
        'defusedxml' \
        'hierarchical-conf==1.0.4' \
        'hive-metastore-client>=1.0.9' \
        'holidays' \
        'importlib-metadata>=1.0.0' \
        'opentelemetry-exporter-otlp-proto-http>=1.22.0' \
        'paramiko' \
        'pendulum' \
        'pymongo>=4.0.0' \
        'PyYAML>=6.0.1' \
        'SQLAlchemy>=1.4.54' \
        'sqlglot>=26.9.0' \
        'tenacity>=8.0.1' \
        'trino>=0.305.0' \
        'Unidecode==1.1.1'

    # delta-spark declares pyspark; EMR already ships PySpark — install the wheel only (same as runtime pyproject note).
    echo "Installing delta-spark 3.3.1 (no-deps; cluster PySpark)..."
    _emr_pip_install install --no-cache-dir --no-deps 'delta-spark==3.3.1'

    echo "Installing bietlejuice core + runtime wheels (no-deps; logger already installed)..."
    _emr_pip_install install --no-cache-dir --no-deps \
        "${TMP_DIR}/wheels/bietlejuice_core-latest-py3-none-any.whl" \
        "${TMP_DIR}/wheels/bietlejuice_runtime-latest-py3-none-any.whl"

    # Runtime wheel omits psycopg2 (DBR bundles it); EMR does not.
    echo "Installing psycopg2-binary (EMR)..."
    _emr_pip_install install --no-cache-dir 'psycopg2-binary==2.9.9'
fi

if [ "${PROVIDER:-}" = "databricks" ]; then
    echo "Pinning requests..."
    _emr_pip_install install --no-cache-dir --ignore-installed "requests==${REQUESTS_VERSION}"
    echo "Installing databricks-sdk for UC REST API sync..."
    _emr_pip_install install --no-cache-dir "databricks-sdk==${DATABRICKS_SDK_VERSION}"
fi

if [ "${PROVIDER:-}" != "databricks" ]; then
    echo "Downloading JARs from S3..."
    POSTGRES_JDBC_JAR="${POSTGRES_JDBC_JAR:-postgresql-42.7.3.jar}"
    aws s3 cp "${ARTIFACTS_BUCKET}/jars/${POSTGRES_JDBC_JAR}" "${TMP_DIR}/${POSTGRES_JDBC_JAR}"
    for jar in \
        "deequ-${DEEQU_JAR_VERSION}-spark-${SPARK_VERSION}.jar" \
        "spark-measure_2.12-0.21.jar" \
        "spark-plugins_2.12-0.2.jar" \
        "spark-plugins_2.12-0.5-SNAPSHOT.jar" \
        "spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar" \
        "${KAFKA_CLIENTS_JAR}" \
        "${SPARK_SQL_KAFKA_JAR}" \
        "${SPARK_TOKEN_PROVIDER_KAFKA_JAR}" \
        "${MYSQL_JDBC_JAR}" \
        "${OPENLINEAGE_JAR}"; do
        aws s3 cp "${ARTIFACTS_BUCKET}/jars/${jar}" "${TMP_DIR}/${jar}" \
            || echo "  WARN: ${jar} not found in S3, skipping"
    done

    echo "Installing delta-spark 3.3.2 to match EMR 7.12 native Delta (no-deps; cluster PySpark)..."
    _emr_pip_install install --no-cache-dir --no-deps 'delta-spark==3.3.2'
    echo "Installing databricks-sdk for UC REST API sync..."
    _emr_pip_install install --no-cache-dir "databricks-sdk==${DATABRICKS_SDK_VERSION}"
    echo "Pinning urllib3 for EMR awscli/botocore compatibility..."
    _emr_pip_install install 'urllib3>=1.25.4,<1.27'

    echo "Installing inmetro ${INMETRO_VERSION} on EMR Python 3.9 (pydeequ, yamale, typing-extensions)..."
    _emr_pip_install install --no-cache-dir --no-deps --ignore-requires-python \
        "${TMP_DIR}/wheels/inmetro-${INMETRO_VERSION}-py3-none-any.whl"
    _emr_pip_install install --no-cache-dir \
        'pydeequ==1.4.0' \
        'yamale==5.2.1' \
        'typing-extensions==4.12.2'

    if ! python3 -c 'import pandas; major, minor, *_ = (int(x) for x in pandas.__version__.split(".")[:2]); raise SystemExit(0 if (major, minor) >= (2, 0) else 1)' 2>/dev/null; then
        echo "Installing pandas>=2.0.0,<3 for inmetro ${INMETRO_VERSION}..."
        _emr_pip_install install --no-cache-dir 'pandas>=2.0.0,<3'
    fi

    # Databricks custom_libraries (pypi + whl + jar + maven) parity — after all
    # aws s3 cp (JARs/default wheels). Extra pip resolver work can break
    # python-dateutil / awscli; cluster YAML and custom whls/jars/maven were
    # fetched early for that reason.
    # Only install when this bootstrap discovered YAML for AIRFLOW_DAG_ID
    # (file/manifest were cleared when discovery was skipped).
    # SKIP_CUSTOM_LIBRARIES=1: wrappers that install pinned stacks themselves.
    # Custom jars (including resolved maven artifacts) are copied into
    # SPARK_JARS_DIRS after platform JARs below.
    if [ "${SKIP_CUSTOM_LIBRARIES:-0}" = "1" ]; then
        echo "SKIP_CUSTOM_LIBRARIES=1; skipping custom_libraries install"
        rm -f "${CLUSTER_YAML_LOCAL}" "${CUSTOM_WHL_MANIFEST}" "${CUSTOM_JAR_MANIFEST}"
    elif [ -n "${AIRFLOW_DAG_ID:-}" ]; then
        _emr_install_custom_pypi_libraries "${CLUSTER_YAML_LOCAL}" "${EMR_IS_VALIDATION:-0}"
        _emr_install_custom_whl_libraries
    fi

    echo "Restoring python-dateutil and urllib3 for awscli compatibility..."
    _emr_pip_install install 'python-dateutil>=2.1,<=2.9.0' 'urllib3>=1.25.4,<1.27'

    SPARK_JARS_DIRS="/usr/lib/spark/jars"
    PYSPARK_JARS=$(python3 -c "import pyspark; print(pyspark.__path__[0] + '/jars')" 2>/dev/null) \
        && SPARK_JARS_DIRS="${SPARK_JARS_DIRS} ${PYSPARK_JARS}"

    echo "Installing PostgreSQL JDBC driver into Spark classpath..."
    for jdir in ${SPARK_JARS_DIRS}; do
        sudo mkdir -p "${jdir}"
        sudo cp "${TMP_DIR}/${POSTGRES_JDBC_JAR}" "${jdir}/${POSTGRES_JDBC_JAR}"
        sudo chmod 644 "${jdir}/${POSTGRES_JDBC_JAR}"
        echo "  PostgreSQL JDBC installed at ${jdir}/${POSTGRES_JDBC_JAR}"
    done

    echo "Installing data-quality, Kafka and MySQL JARs into Spark classpath..."
    for jar in \
        "deequ-${DEEQU_JAR_VERSION}-spark-${SPARK_VERSION}.jar" \
        "spark-measure_2.12-0.21.jar" \
        "spark-plugins_2.12-0.2.jar" \
        "spark-plugins_2.12-0.5-SNAPSHOT.jar" \
        "spark-cluster-metrics_2.12-0.1-SNAPSHOT.jar" \
        "${KAFKA_CLIENTS_JAR}" \
        "${SPARK_SQL_KAFKA_JAR}" \
        "${SPARK_TOKEN_PROVIDER_KAFKA_JAR}" \
        "${MYSQL_JDBC_JAR}" \
        "${OPENLINEAGE_JAR}"; do
        if [ -f "${TMP_DIR}/${jar}" ]; then
            for jdir in ${SPARK_JARS_DIRS}; do
                sudo cp "${TMP_DIR}/${jar}" "${jdir}/${jar}"
                sudo chmod 644 "${jdir}/${jar}"
            done
            echo "  Installed ${jar}"
        else
            echo "  WARN: ${jar} not downloaded, skipping"
        fi
    done

    # DAG-level custom_libraries jar/maven: Databricks libraries API parity on EMR.
    if [ "${SKIP_CUSTOM_LIBRARIES:-0}" != "1" ] && [ -n "${AIRFLOW_DAG_ID:-}" ]; then
        _emr_install_custom_jar_libraries
    fi
fi

echo "Validating installation..."

if ! $PIP_EXEC show databricks-sdk; then
    echo "Error: databricks-sdk is not installed."
    exit 1
fi
if [ "${PROVIDER:-}" = "databricks" ]; then
    :
else
    if ! $PIP_EXEC show bietlejuice-core; then
        echo "Error: bietlejuice-core is not installed."
        exit 1
    fi
    if ! $PIP_EXEC show bietlejuice-runtime; then
        echo "Error: bietlejuice-runtime is not installed."
        exit 1
    fi
    if ! $PIP_EXEC show quintoandar-logger; then
        echo "Error: quintoandar-logger is not installed."
        exit 1
    fi
    if ! $PIP_EXEC show inmetro; then
        echo "Error: inmetro is not installed."
        exit 1
    fi
    if ! python3 -c 'import psycopg2; print("psycopg2", psycopg2.__version__)'; then
        echo "Error: psycopg2 import failed after bootstrap."
        exit 1
    fi
    echo "Smoke-testing inmetro ${INMETRO_VERSION} on python3..."
    if ! python3 -c "import inmetro; from inmetro.config_reader import ConfigReader; import inspect; assert 'content' in inspect.signature(ConfigReader.__init__).parameters; print('inmetro', inmetro.__version__)"; then
        echo "Error: inmetro smoke test failed after bootstrap."
        exit 1
    fi
fi

echo "DONE: bootstrap finished."

