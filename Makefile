# Disable all the default make stuff
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

GOPRIVATE := github.com/humanitec

## Display help menu
.PHONY: help
help:
	@echo Documented Make targets:
	@perl -e 'undef $$/; while (<>) { while ($$_ =~ /## (.*?)(?:\n# .*)*\n.PHONY:\s+(\S+).*/mg) { printf "\033[36m%-30s\033[0m %s\n", $$2, $$1 } }' $(MAKEFILE_LIST) | sort

# ------------------------------------------------------------------------------
# NON-PHONY TARGETS
# ------------------------------------------------------------------------------

.score-compose/state.yaml:
	score-compose init --no-sample

.score-k8s/state.yaml:
	score-k8s init --no-sample

compose.yaml: score-node.yaml score-python.yaml .score-compose/state.yaml Makefile
ifeq (, $(shell which score-compose))
	$(error "No score-compose in $$PATH, please follow https://docs.score.dev/docs/get-started/install/")
endif
ifneq (, $(shell [[ "$(shell score-compose --version)" =~ "0\.(\d\.|11\.|12\.|13\.|14\.|15.0)" ]] && echo matched))
	$(error "Version of score-compose is too old, please follow https://docs.score.dev/docs/get-started/install/")
endif
	score-compose generate score-node.yaml --build='nodeapp={"context": "./node"}'
	score-compose generate score-python.yaml --build='pythonapp={"context": "./python"}'
	yq --inplace '(.services) += (.services |																		\
		with_entries(select((.value | has("hostname")) and (.value.annotations | has("dapr.io/enabled")))) | 		\
		with_entries(. as $$e | .key |= . + "-sidecar"| .value |= {													\
			"image": "daprio/daprd:latest", 																		\
			"command": [																							\
				"./daprd",																							\
				("--app-id=" + ($$e.value.annotations."dapr.io/app-id" // error("missing app-id annotation"))),		\
				("--app-port=" + ($$e.value.annotations."dapr.io/app-port" // "")),									\
				("--enable-api-logging=" + ($$e.value.annotations."dapr.io/enable-api-logging" // "false")),		\
				"--placement-host-address=placement:50006",															\
				"--resources-path=/components"																		\
			], 																										\
			"network_mode": ("service:" + $$e.key),																	\
			"volumes": [".score-compose/mounts/dapr-components/:/components"],										\
			"depends_on": ["placement"]																				\
		}))' compose.yaml
	yq --inplace '.services.placement = {"image": "daprio/dapr", "command": ["./placement", "-port", "50006"], "ports": ["50006:50006"]}' compose.yaml

manifests.yaml: score-node.yaml score-python.yaml .score-k8s/state.yaml .score-k8s/00-custom.provisioners.yaml
ifeq (, $(shell which score-k8s))
	$(error "No score-k8s in $$PATH, please follow https://docs.score.dev/docs/get-started/install/")
endif
ifneq (, $(shell [[ "$(shell score-k8s --version)" =~ "0\.(1\.[01])" ]] && echo matched))
	$(error "Version of score-k8s is too old, please follow https://docs.score.dev/docs/get-started/install/")
endif
	score-k8s generate score-node.yaml score-python.yaml

# ------------------------------------------------------------------------------
# PHONY TARGETS
# ------------------------------------------------------------------------------

## Remove all ephemeral state
.PHONY: clean
clean:
	find .score-compose ! -name 00-custom.provisioners.yaml ! -name .score-compose -exec rm -rfv {} +
	find .score-k8s ! -name 00-custom.provisioners.yaml ! -name .score-k8s -exec rm -rfv {} +
	rm -rfv compose.yaml manifests.yaml

## Build the output manifests
.PHONY: build
build: compose.yaml manifests.yaml
