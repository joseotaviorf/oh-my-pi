############# PYTHON2 commands #######################

.PHONY: environment-python2
environment-python2:
	@pyenv install -s 2.7.12
	@pyenv virtualenv 2.7.12 bi-etl-ejuice-python2
	@pyenv local bi-etl-ejuice-python2

.PHONY: requirements-python2
requirements-python2:
	@python -m pip install -r requirements.txt
	@make requirements-test-python2
	@make requirements-lint-python2

.PHONY: requirements-test-python2
requirements-test-python2:
	@python -m pip install -r requirements_test.txt

.PHONY: requirements-lint-python2
requirements-lint-python2:
	@python -m pip install -q flake8==3.5.0

.PHONY: check-style-python2
check-style-python2:
	@echo ""
	@echo "Check Style"
	@echo "=========="
	@echo ""
	@python -m flake8 --config=setup.cfg

.PHONY: unit-tests-python2
unit-tests-python2:
	@echo ""
	@echo "Automated Tests"
	@echo "=========="
	@echo ""
	@python -m pytest --cov=bietlejuice/jobs/etl --cov-report html:htmlcov --cov-fail-under=25 --cov-config .coveragerc tests

############# PYTHON3 commands #######################

.PHONY: environment-python3
environment-python3:
	@pyenv install -s 3.6.7
	@pyenv virtualenv 3.6.7 bi-etl-ejuice-python3
	@pyenv local bi-etl-ejuice-python3

.PHONY: requirements-python3
requirements-python3:
	@python -m pip install -U -r requirements3.txt --extra-index-url https://quintoandar.github.io/python-package-server/
	@make requirements-test-python3
	@make requirements-lint-python3

.PHONY: requirements-test-python3
requirements-test-python3:
	@python -m pip install -r requirements3_test.txt

.PHONY: requirements-lint-python3
requirements-lint-python3:
	@python -m pip install -r requirements3_lint.txt

.PHONY: lint-python3
## run black to fix code style
lint-python3:
	@python -m black bietlejuice/jobs/composer/

.PHONY: check-style-python3
## check style with flake8 and black
check-style-python3:
	@echo ""
	@echo "Check Style"
	@echo "=========="
	@echo ""
	@python -m black --check bietlejuice/jobs/composer/
	@python -m flake8 --config=setup3.cfg bietlejuice/jobs/composer/

.PHONY: package-python3
package-python3:
	@PYTHONPATH=. python -m setup3 sdist bdist_wheel

.PHONY: unit-tests-python3
unit-tests-python3:
	@echo ""
	@echo "Automated Tests"
	@echo "=========="
	@echo ""
	@python -m pytest --cov=bietlejuice/jobs/composer --cov-fail-under=10 --cov-config .coveragerc tests3

############# common commands #######################

.PHONY: cov-badge
## build coverage badge
cov-badge:
	@echo ""
	@echo "Building Coverage Badge"
	@echo "=========="
	@echo ""
	@coverage-badge -o badge-lines.svg

.PHONY: clean
## delete all compiled python files
clean:
	@find ./ -type d -name '.pytest_cache' -exec rm -rf {} +;
	@find ./ -type d -name 'build' -exec rm -rf {} +;
	@find ./ -type d -name 'dist' -exec rm -rf {} +;
	@find ./ -type d -name 'python_logger.egg-info' -exec rm -rf {} +;
	@find ./ -type d -name 'htmlcov' -exec rm -rf {} +;
	@find ./ -type f -name 'coverage.xml' -exec rm -f {} \;
	@find ./ -type f -name 'coverage-badge.svg' -exec rm -f {} \;
	@find ./ -type f -name '.coverage' -exec rm -f {} \;
	@find ./ -type f -name '.version' -exec rm -f {} \;
	@find ./ -type f -name '.package_name' -exec rm -f {} \;
	@find ./ -type f -name '*.pyc' -exec rm -f {} \;
	@find ./ -type f -name '*~' -exec rm -f {} \;

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