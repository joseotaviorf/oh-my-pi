###############################################################################
###################### Local Airflow Docker environment #######################
###############################################################################
branch ?= forno
.PHONY: clone-local-airflow-plugins
## Clones QuintoAndar's custom Airflow Plugins (https://github.com/quintoandar/airflow-plugins) into a local plugins folder.
## May receive an optional `branch={branch}` argument to clone a specified branch. Defaults to `forno`.
clone-local-airflow-plugins:
	@echo "Cloning 'airflow-plugins' from branch '$(branch)'"
	@echo "=========="
	@echo ""
	@rm -fR ./local/astro/plugins || true
	@rm -fR ./local/astro/plugins_temp || true
	@git clone -b $(branch) --quiet --depth 1 https://github.com/quintoandar/airflow-plugins.git ./local/astro/plugins_temp
	@cp -Rf ./local/astro/plugins_temp/quintoandar_airflow_plugins/ ./local/astro/plugins
	@rm -fR ./local/astro/plugins_temp
	@rm -fR ./local/astro/plugins/databricks_plugin.py
	@echo "Cloning succeeded at ./local/astro/plugins"

.PHONY: setup-bietlejuice
setup-bietlejuice:
	@echo "Setup bietlejuice at local airflow deployment"
	@echo "=========="
	@rm -fR ./local/astro/dags || true
	@rm -fR ./local/astro/bietlejuice || true
	@rm -fR ./local/astro/scripts || true
	@cp -Rf ./dags/ ./local/astro/dags
	@cp -Rf ./bietlejuice/ ./local/astro/bietlejuice
	@cp -Rf ./scripts/ ./local/astro/scripts

.PHONY: setup-local-variables
## receives and sets up local shell variables to store token credentials used in the local Airflow environment.
## Variables are set either into ~/.zshrc or into ~/.bashrc, according to the default shell terminal used.
setup-local-variables:
	@echo "Setting up local variables"
	@echo "=========="
	@echo ""
	@if [ -z "${GITHUB_TOKEN}" ]; then\
		if [ -f $$HOME/.zshrc ]; then SHELL_RC="$$HOME/.zshrc"; else SHELL_RC="$$HOME/.bashrc"; fi;\
		printf 'Enter your GitHub token \e]8;;https://docs.github.com/en/enterprise-server@3.4/authentication/keeping-your-account-and-data-secure/creating-a-personal-access-token\e\\[click here for info]\e]8;;\e\\: ';\
		read -r GITHUB_TOKEN;\
		echo export GITHUB_TOKEN=$$GITHUB_TOKEN >> $$SHELL_RC;\
	fi
	@if [ -z "${DATABRICKS_TOKEN}" ]; then\
		if [ -f $$HOME/.zshrc ]; then SHELL_RC="$$HOME/.zshrc"; else SHELL_RC="$$HOME/.bashrc"; fi;\
		printf 'Enter your Databricks token \e]8;;https://docs.databricks.com/dev-tools/api/latest/authentication.html#generate-a-personal-access-token\e\\[click here for info]\e]8;;\e\\: ';\
		read -r DATABRICKS_TOKEN;\
		echo export DATABRICKS_TOKEN=$$DATABRICKS_TOKEN >> $$SHELL_RC;\
	fi
	@if [ -z "${DATABRICKS_USERNAME}" ]; then\
		if [ -f $$HOME/.zshrc ]; then SHELL_RC="$$HOME/.zshrc"; else SHELL_RC="$$HOME/.bashrc"; fi;\
		printf 'Enter your Databricks Username (email@quintoandar.com.br) ';\
		read -r DATABRICKS_USERNAME;\
		echo export DATABRICKS_USERNAME=$$DATABRICKS_USERNAME >> $$SHELL_RC;\
	fi
	
	@echo "All variables set!"
	@echo "~> Restart your shell to apply changes!"

.PHONY: import-variables-and-connections
import-variables-and-connections:
	@echo "Import Variables and Connections"
	@cd ./local/astro; \
	sh import_conn_vars.sh

branch ?= forno
.PHONY: run-local-environment
## runs a local Airflow environment containing both bi-etl-ejuice DAGs and QuintoAndar's custom Airflow Plugins.
## May receive an optional `branch={branch}` argument to clone a specified branch of Airflow Plugins repo. Defaults to `forno`.
run-local-environment:
	@make setup-bietlejuice
	@make clone-local-airflow-plugins branch=$(branch)
	@echo "Recreating local Airflow environment"
	@echo "=========="
	@echo ""
	@cd ./local/astro; \
	astro dev start --build-secrets id=GITHUB_TOKEN
	@make import-variables-and-connections

.PHONY: restart-local-environment
restart-local-environment:
	@echo "Restart local Airflow environment"
	@make setup-bietlejuice
	@cd ./local/astro; \
	astro dev restart --build-secrets id=GITHUB_TOKEN 

.PHONY: stop-local-environment
stop-local-environment:
	@echo "Restart local Airflow environment"
	@cd ./local/astro; \
	astro dev stop
	
.PHONY: stop-local-environment
kill-local-environment:
	@echo "Delete local Airflow environment"
	@cd ./local/astro; \
	astro dev kill

###############################################################################
###################### Local Tests Docker environment #########################
###############################################################################
.PHONY: _build-tests-environment
_build-tests-environment:
	@docker build -f local/tests-environment.Dockerfile -t bietlejuice-tests-local --build-arg GITHUB_TOKEN=${GITHUB_TOKEN} .

.PHONY: run-tests-environment
run-tests-environment:
	@make _build-tests-environment
	@docker run bietlejuice

###############################################################################
###################### Local environment S3 upload ############################
###############################################################################
.PHONY: upload-local-wheel
upload-local-wheel:
	@python3 -m setup sdist bdist_wheel
	@python3 local/upload_local_whl_to_s3.py

.PHONY: upload-local-spark-jobs
upload-local-spark-jobs:
	@python3 local/upload_local_spark_jobs_to_s3.py databricks.s3.forno.data.quintoandar.com.br

.PHONY: upload-local-package
upload-local-package:
	@python3 local/upload_local_spark_jobs_to_s3.py
	@python3 -m setup sdist bdist_wheel
	@python3 local/upload_local_whl_to_s3.py

###############################################################################
###################### Local Python environment ###############################
###############################################################################
.PHONY: environment
environment:
	@echo ""
	@echo "Creating Python environment for bi-etl-ejuice package"
	@echo "=========="
	@echo ""
	@pyenv install -s 3.8.12
	@pyenv virtualenv 3.8.12 bi-etl-ejuice
	@pyenv local bi-etl-ejuice
	@echo "-> Python virtual environment 'bi-etl-ejuice' has been set as the current virtualenv."

###############################################################################
###################### Requirements setup #####################################
###############################################################################
.PHONY: requirements
requirements:
	@echo ""
	@echo "Installing packages"
	@echo "=========="
	@echo ""
	@python -m pip install -U -r requirements.txt --extra-index-url https://quintoandar.github.io/python-package-server/
	@make requirements-lint

.PHONY: requirements-test
requirements-test:
	@echo ""
	@echo "Installing tests packages"
	@echo "=========="
	@echo ""
	@python -m pip install -r requirements_test.txt  --extra-index-url https://quintoandar.github.io/python-package-server/

.PHONY: requirements-lint
requirements-lint:
	@echo ""
	@echo "Installing lint packages"
	@echo "=========="
	@echo ""
	@python -m pip install -r requirements_lint.txt

.PHONY: requirements-scripts
requirements-scripts:
	@echo ""
	@echo "Installing scripts packages"
	@echo "=========="
	@echo ""
	@python -m pip install -U -r requirements_scripts.txt --extra-index-url https://quintoandar.github.io/python-package-server/

###############################################################################
###################### Package setup ##########################################
###############################################################################
.PHONY: package
package:
	@make requirements
	@echo ""
	@echo "Creating 'requirements-freeze.txt' to prepare building dependencies"
	@echo "=========="
	@echo ""
	@python -m pip freeze > requirements-freeze.txt
	@echo ""
	@echo "Creating wheel for bi-etl-ejuice"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python -m setup sdist bdist_wheel

###############################################################################
###################### Style handling #########################################
###############################################################################
.PHONY: lint
## run black to fix code style
lint:
	@echo ""
	@echo "Running lint in all files from <bietlejuice/>"
	@echo "=========="
	@echo ""
	@python -m black bietlejuice/ tests/unit/ --exclude=".*\/__dags_template__.py"

.PHONY: check-style
## check style with flake8 and black
check-style:
	@echo ""
	@echo "Running Check Style"
	@echo "=========="
	@echo ""
	@python -m black --check bietlejuice/ tests/unit/ --exclude=".*\/__dags_template__.py" && echo "\n\nSuccess\n" || (echo "\n\nFailure\n\nRun \"make lint\" to apply style formatting to your code\n" && exit 1)
	@python -m flake8 --config=setup.cfg bietlejuice/ tests/unit/

###############################################################################
###################### Tests commands #########################################
###############################################################################
.PHONY: tests
## run all unit and integration tests with coverage report
tests:
	@python -m pytest -W ignore::DeprecationWarning --cov-config=.coveragerc --cov=bietlejuice/ --cov-report term --cov-report html:htmlcov --cov-report xml:coverage.xml tests
	@python -m coverage xml -i

.PHONY: unit-tests
unit-tests:
	@echo ""
	@echo "Unit Tests"
	@echo "=========="
	@echo ""
	@python -m pytest -W ignore::DeprecationWarning --cov-config=.coveragerc --cov-report term --cov-report html:htmlcov --cov=bietlejuice/ --cov-fail-under=35 tests/unit/

.PHONY: integration-tests
## run integration tests with coverage report
integration-tests:
	@echo ""
	@echo "Integration Tests"
	@echo "================="
	@echo ""
	@python -m pytest -W ignore::DeprecationWarning --cov-config=.coveragerc --cov-report term --cov-report xml:integration-tests-cov.xml --cov=bietlejuice/ --cov-fail-under=0 tests/integration

.PHONY: files-validation
files-validation:
	@echo ""
	@echo "Validation Files Tests"
	@echo "=========="
	@echo ""
	@python -m pytest tests/files_validation/

###############################################################################
###################### Validations commands ###################################
###############################################################################
.PHONY: validate-dags-dependencies
validate-dags-dependencies:
	@echo ""
	@echo "Validating DAGs dependencies"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/ci_cd/validate_dags_dependencies.py

.PHONY: validate-dependency-file-correctness
## validates the correctness of the dags/dependencies.yaml file, according to the FileDependencyGenerator.
validate-dependency-file-correctness:
	@echo ""
	@echo "Validating correctness of dags/dependencies.yaml file"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/dependency_handling/validate_dependency_file_correctness.py

level ?= warning
.PHONY: validate-dag-declaration-files
## validates the content of DAG declaration YAML files, returning which keys of which files are not following requirements.
## May receive an optional `level={level}` argument to declare the expected logging level of the validation.
validate-dag-declaration-files:
	@echo ""
	@echo "Validating DAG declaration files"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/ci_cd/airflow_dag_builder/validate_dag_declaration_files.py -l $(level)

## validates if the DAGs are using our current standards, such as using DAG Builder or CDC.
validate-dags-up-to-standard:
	@echo ""
	@echo "Validating DAG declaration files"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/dag_standard_validation/validate_dags_following_current_standards.py

.PHONY: validate-metadata-files-content
validate-metadata-files-content:
	@echo ""
	@echo "Validating if new/modified metadata files follow the metadata file schema"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@PYTHONPATH=. python3 scripts/governance_metadata_validation/validate_metadata_files_content.py -b "$(CI_COMMIT_BRANCH)" -v

.PHONY: validate-metadata-files-exist
validate-metadata-files-exist:
	@echo ""
	@echo "Validating if new/modified query files have corresponding metadata file defined"
	@echo "=========="
	@echo ""
	@git fetch --no-tags origin +refs/heads/master
	@PYTHONPATH=. python3 scripts/governance_metadata_validation/validate_metadata_files_exist.py -b "$(CI_COMMIT_BRANCH)" -v

###############################################################################
###################### Common commands ########################################
###############################################################################
dag_name ?="*"
.PHONY: create-dag-files
## creates the DAG Python files from the DAG declaration YAML files, as of `{dag_name}_dag.py`.
## May receive an optional `dag_name={dag_name}` argument to create only the Python DAG file of the provided DAG.
create-dag-files:
	@echo ""
	@echo "Creating the DAGs' Python files"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/ci_cd/airflow_dag_builder/create_dag_files.py -d $(dag_name)

.PHONY: cov-badge
## build coverage badge
cov-badge:
	@echo ""
	@echo "Building Coverage Badge"
	@echo "=========="
	@echo ""
	@coverage-badge -o coverage_badge.svg

.PHONY: clean
## delete all compiled python files
clean:
	@find ./ -type d -name '.pytest_cache' -exec rm -rf {} +;
	@find ./ -type d -name 'build' -exec rm -rf {} +;
	@find ./ -type d -name 'dist' -exec rm -rf {} +;
	@find ./ -type d -name 'python_logger.egg-info' -exec rm -rf {} +;
	@find ./ -type d -name 'metastore_db' -exec rm -rf {} +;
	@find ./ -type d -name 'htmlcov' -exec rm -rf {} +;
	@find ./ -type f -name 'coverage.xml' -exec rm -f {} \;
	@find ./ -type f -name 'coverage-badge.svg' -exec rm -f {} \;
	@find ./ -type f -name '.coverage' -exec rm -f {} \;
	@find ./ -type f -name '*-cov.*' -exec rm -f {} \;
	@find ./ -type f -name '*derby.log' -exec rm -f {} \;
	@find ./ -type f -name '.version' -exec rm -f {} \;
	@find ./ -type f -name '.package_name' -exec rm -f {} \;
	@find ./ -type f -name '*.pyc' -exec rm -f {} \;
	@find ./ -type f -name '*~' -exec rm -f {} \;
	@find ./dags/ -type f -name '*_dag.py' -exec rm -f {} \;
	@find ./dags/ -empty -type d -delete

.PHONY: help
# Inspired by <http://marmelab.com/blog/2016/02/29/auto-documented-makefile.html>
# sed script explained:
# /^##/:
# 	* save line in hold space
# 	* purge line
# 	* Loop:
# 		* append newline + line to hold space
# 		* go to next line
# 		* if line starts with doc comment, strip comment character off and loop
# 	* remove target prerequisites
# 	* append hold space (+ newline) to line
# 	* replace newline plus comments by `---`
# 	* print line
# Separate expressions are necessary because labels cannot be delimited by
# semicolon; see <http://stackoverflow.com/a/11799865/1968>
help:
	@echo "$$(tput bold)Available rules:$$(tput sgr0)"
	@echo
	@sed -n -e "/^## / { \
		h; \
		s/.*//; \
		:doc" \
		-e "H; \
		n; \
		s/^## //; \
		t doc" \
		-e "s/:.*//; \
		G; \
		s/\\n## /---/; \
		s/\\n/ /g; \
		p; \
	}" ${MAKEFILE_LIST} \
	| LC_ALL='C' sort --ignore-case \
	| awk -F '---' \
		-v ncol=$$(tput cols) \
		-v indent=19 \
		-v col_on="$$(tput setaf 6)" \
		-v col_off="$$(tput sgr0)" \
	'{ \
		printf "%s%*s%s ", col_on, -indent, $$1, col_off; \
		n = split($$2, words, " "); \
		line_length = ncol - indent; \
		for (i = 1; i <= n; i++) { \
			line_length -= length(words[i]) + 1; \
			if (line_length <= 0) { \
				line_length = ncol - indent - length(words[i]) - 1; \
				printf "\n%*s ", -indent, " "; \
			} \
			printf "%s ", words[i]; \
		} \
		printf "\n"; \
	}' \
	| more $(shell test $(shell uname) = Darwin && echo '--no-init --raw-control-chars')

.DEFAULT_GOAL := help


.PHONY: dependencies-file
## Automatically generate dependencies.yaml file based on the queries and config files
dependencies-file:
	@echo ""
	@echo "Generating dependencies.yaml file"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/dependency_handling/automate_dependencies.py

.PHONY: freeze-dependency-exceptions
## Automatically generate dependency_exceptions/manual_modifications.yaml, based on the dependencies.yaml file
freeze-dependency-exceptions:
	@echo ""
	@echo "Generating dependencies.yaml file"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/dependency_handling/freeze_dependency_exceptions.py


.PHONY: generate-enrich-dag-declaration
## Automatically generates the DAG Declaration yaml file of an existing enrich DAG, by reading the Python file and other configuration files.
generate-enrich-dag-declaration:
	@echo ""
	@echo "Generating Enrich dag declaration based on dag file"
	@echo "=========="
	@echo ""
	@PYTHONPATH=. python3 scripts/artifact_generation/generate_enrich_template_from_py_file.py -d $(dag_name)
