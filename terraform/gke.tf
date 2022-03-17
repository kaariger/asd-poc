/**
 * Copyright 2022 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

module "enabled_google_apis" {
  source  = "terraform-google-modules/project-factory/google//modules/project_services"
  version = "~> 11.3"

  project_id                  = var.project
  disable_services_on_destroy = false

  activate_apis = [
    "compute.googleapis.com",
    "container.googleapis.com",
    "gkehub.googleapis.com",
    "anthosconfigmanagement.googleapis.com",
    "meshconfig.googleapis.com"
  ]
}

module "gke" {
  source             = "terraform-google-modules/kubernetes-engine/google"
  version            = "~> 20.0"
  project_id         = module.enabled_google_apis.project_id
  name               = var.cluster_name
  region             = var.region
  zones              = [var.zone]
  initial_node_count = 4
  network            = "default"
  subnetwork         = "default"
  ip_range_pods      = ""
  ip_range_services  = ""

  depends_on = [
    module.enabled_google_apis
  ]
}

data "google_client_config" "default" {}

provider "kubernetes" {
  host                   = "https://${module.gke.endpoint}"
  token                  = data.google_client_config.default.access_token
  cluster_ca_certificate = base64decode(module.gke.ca_certificate)
}

# this is needed as a workaround due to https://github.com/terraform-google-modules/terraform-google-kubernetes-engine/issues/1181
locals {
  cluster_name = element(split("/", module.gke.cluster_id), length(split("/", module.gke.cluster_id)) - 1)
}

module "asm" {
  source                    = "terraform-google-modules/kubernetes-engine/google//modules/asm"
  version                   = "~> 20.0"
  project_id                = module.enabled_google_apis.project_id
  cluster_name              = local.cluster_name
  cluster_location          = module.gke.location
  multicluster_mode         = "connected"
  enable_cni                = true
  enable_fleet_registration = true
  enable_mesh_feature       = true
}

module "boa-secret" {
  source = "terraform-google-modules/gcloud/google//modules/kubectl-wrapper"

  project_id              = module.enabled_google_apis.project_id
  cluster_name            = module.gke.name
  cluster_location        = module.gke.location
  kubectl_create_command  = "kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/bank-of-anthos/main/extras/jwt/jwt-secret.yaml"
  kubectl_destroy_command = "kubectl delete -f https://raw.githubusercontent.com/GoogleCloudPlatform/bank-of-anthos/main/extras/jwt/jwt-secret.yaml"
}

module "boa-istio" {
  source = "terraform-google-modules/gcloud/google//modules/kubectl-wrapper"

  project_id              = module.enabled_google_apis.project_id
  cluster_name            = module.gke.name
  cluster_location        = module.gke.location
  kubectl_create_command  = "kubectl apply -f https://raw.githubusercontent.com/GoogleCloudPlatform/bank-of-anthos/main/istio-manifests/frontend-ingress.yaml"
  kubectl_destroy_command = "kubectl delete -f https://raw.githubusercontent.com/GoogleCloudPlatform/bank-of-anthos/main/istio-manifests/frontend-ingress.yaml"
}