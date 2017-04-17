SHELL = /bin/bash

CI_BUILD_NUMBER ?= $(USER)-snapshot
VERSION ?= $(CI_BUILD_NUMBER)
DATE = $(shell date +%Y-%m-%dT%H_%M_%S)

# Deployment target information
# Override these in an env.
ZONE ?= us-east1-b
CLUSTER ?= your-cluster
PROJECT ?= your-project

# Tells our deployment to fail or not.
FAIL_REQUEST ?= false
ENDPOINT_NAME = cloud-endpoint-blt-best.mup.zone
ENDPOINT_REVISON = invalid

help:
	@echo Public targets:
	@grep -E '^[^_]{2}[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'
	@echo "Private targets: (use at own risk)"
	@grep -E '^__[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[35m%-20s\033[0m %s\n", $$1, $$2}'

version: ## Convenience for knowing version in current context.
	@echo $(VERSION)

deploy: __get-credentials __deploy-only ## Does full deployment.

deploy-endpoint: ## Fills openapi template and deploys to gcloud svc management.
	VERSION=$(VERSION) \
		envtpl < infra/openapi.yaml > target/openapi.yaml
	gcloud service-management deploy target/openapi.yaml

latest-revision: ## Prints latest gcloud svc revision
	@gcloud service-management --project meetup-dev describe $(ENDPOINT_NAME) | grep id: | awk '{print $$2}'

view-endpoint:
	gcloud service-management --project meetup-dev describe $(ENDPOINT_NAME)

__set-revision: ## Retrieves latest rev from google and sets to internal var.
	$(eval ENDPOINT_REVISION=$(shell make latest-revision))

__deploy-only: ## Does deployment without setting creds. (current kubectl ctx)
	@kubectl apply -f infra/blt-best-ns.yaml
	@kubectl apply -f infra/cloud-endpoint-svc.yaml
	@kubectl apply -f infra/cloud-endpoint-cm.yaml

# Perform our deployment.
	@DATE=$(DATE) \
		FAIL_REQUEST=$(FAIL_REQUEST) \
		envtpl < infra/cloud-endpoint-deploy.yaml | kubectl apply -f -

# Check on deployment with a 1 min timeout (new replicas never came up)
#  if we timeout rollback and error out.
	@timeout 1m kubectl rollout status deploy cloud-endpoint -n blt-best || { \
		if [ "$$?" == "124" ]; then \
			echo "Deployment timed out, rolling back"; \
			kubectl rollout undo deploy cloud-endpoint -n blt-best; \
		fi; \
		false; \
	}

__get-credentials: ## Set kubectl ctx to curent cluster config.
	@gcloud container clusters get-credentials \
		--zone $(ZONE) \
		--project $(PROJECT) \
		$(CLUSTER) 2> /dev/null
