terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
  }
}

provider "coder" {
}

variable "use_kubeconfig" {
  type        = bool
  description = <<-EOF
  Use host kubeconfig? (true/false)

  Set this to false if the Coder host is itself running as a Pod on the same
  Kubernetes cluster as you are deploying workspaces to.

  Set this to true if the Coder host is running outside the Kubernetes cluster
  for workspaces.  A valid "~/.kube/config" must be present on the Coder host.
  EOF
  default     = false
}

variable "namespace" {
  type        = string
  default= "coder"
  description = "The Kubernetes namespace to create workspaces in (must exist prior to creating workspaces). If the Coder host is itself running as a Pod on the same Kubernetes cluster as you are deploying workspaces to, set this to the same namespace."
}

data "coder_parameter" "cpu" {
  name         = "cpu"
  display_name = "CPU"
  description  = "The number of CPU cores"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 Cores"
    value = "2"
  }
  option {
    name  = "4 Cores"
    value = "4"
  }
  option {
    name  = "6 Cores"
    value = "6"
  }
  option {
    name  = "8 Cores"
    value = "8"
  }
}

data "coder_parameter" "memory" {
  name         = "memory"
  display_name = "Memory"
  description  = "The amount of memory in GB"
  default      = "2"
  icon         = "/icon/memory.svg"
  mutable      = true
  option {
    name  = "2 GB"
    value = "2"
  }
  option {
    name  = "4 GB"
    value = "4"
  }
  option {
    name  = "6 GB"
    value = "6"
  }
  option {
    name  = "8 GB"
    value = "8"
  }
}

data "coder_parameter" "home_disk_size" {
  name         = "home_disk_size"
  display_name = "Home disk size"
  description  = "The size of the home disk in GB"
  default      = "1"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 10
  }
}

provider "kubernetes" {
  # Authenticate via ~/.kube/config or a Coder-specific ServiceAccount, depending on admin preferences
  config_path = var.use_kubeconfig == true ? "~/.kube/config" : null
}

data "coder_workspace" "me" {}

data "coder_parameter" "image" {
  name        = "Image"
  icon        = "/icon/docker.png"
  order       = 4
  default     = "mcr.microsoft.com/vscode/devcontainers/base:ubuntu"
  description = "See [Development Container Images](https://hub.docker.com/_/microsoft-vscode-devcontainers) if you don't know where to start"
  type        = "string"
 # validation {
 #   regex = "[a-z]+"
 #   error = "Image cannot be left blank!"
 # }
  mutable = true
 # option {
 #   name        = "sharkymark/envbuilder-starter-devcontainer"
 #   description = "An example repository for getting started with devcontainer.json and envbuilder."
 #   value       = "https://github.com/sharkymark/envbuilder-starter-devcontainer"
 #  # icon        = "https://avatars.githubusercontent.com/u/95932066?s=200&v=4"
 # }
  option {
    name        = "ubuntu"
    description = "Ubuntu"
    value       = "mcr.microsoft.com/vscode/devcontainers/base:ubuntu"
  }
  option {
    name        = "go"
    description = "Golang"
    value       = "mcr.microsoft.com/vscode/devcontainers/go:latest"
   # icon        = "https://cdn.worldvectorlogo.com/logos/golang-gopher.svg"
  }
  option {
    name        = "javascript-node:16"
    description = "Node.js"
    value       = "mcr.microsoft.com/vscode/devcontainers/javascript-node:16"
   # icon        = "https://cdn.freebiesupply.com/logos/large/2x/nodejs-icon-logo-png-transparent.png"
  } 
  option {
    name        = "Python"
    description = "Python"
    value       = "mcr.microsoft.com/vscode/devcontainers/python:latest"
 #  # icon        = "https://assets.stickpng.com/images/58480979cef1014c0b5e4901.png"
  }
  option {
    name        = "Custom"
    icon        = "/emojis/1f5c3.png"
    description = "Specify a custom image"
    value       = "custom"
  }
}
locals {
  folder_name = try(element(split("/", data.coder_parameter.repo.value), length(split("/", data.coder_parameter.repo.value)) - 1), "")
}


resource "coder_agent" "main" {
  os                     = "linux"
  arch                   = "amd64"
  startup_script_timeout = 180
  dir                    = "/workspaces/${local.folder_name}"
  startup_script         = <<-EOT
    set -e

    # Set /workspaces as the standard home directory
    sudo mkdir -p /workspaces
    sudo chown -R $USER /workspaces
    sudo usermod -d /workspaces $USER
    if [ ! -f "/workspaces/.bashrc" ]; then
      # Copy default dotfiles
      cp -rT $HOME /workspaces/.
    fi
    sudo rm -r $HOME
    export HOME=/workspaces
    cd $HOME

    if test -z "${data.coder_parameter.repo.value}" 
    then
      echo "No git repo specified, skipping"
    else
      if [ ! -d "${local.folder_name}" ] 
      then
        echo "Cloning git repo..."
        git clone ${data.coder_parameter.repo.value}
      fi
      cd ${local.folder_name}
    fi

    # install and start code-server
    curl -fsSL https://code-server.dev/install.sh | sh -s -- --method=standalone --prefix=/tmp/code-server --version 4.8.3
    /tmp/code-server/bin/code-server --auth none --port 13337 . >/tmp/code-server.log 2>&1 &


    # install VS Code
    curl -Lk 'https://code.visualstudio.com/sha/download?build=stable&os=cli-alpine-x64' --output vscode_cli.tar.gz
    mkdir -p /tmp/vscode-cli
    tar -xf vscode_cli.tar.gz -C /tmp/vscode-cli
    rm vscode_cli.tar.gz
    # start the web server on a specific port
    /tmp/vscode-cli/code serve-web --port 13338 --without-connection-token  --accept-server-license-terms >/tmp/vscode-web.log 2>&1 &


  EOT


  # These environment variables allow you to make Git commits right away after creating a
  # workspace. Note that they take precedence over configuration defined in ~/.gitconfig!
  # You can remove this block if you'd prefer to configure Git manually or using
  # dotfiles. (see docs/dotfiles.md)
  env = {
    "DOTFILES_URI" = data.coder_parameter.dotfiles_url.value != "" ? data.coder_parameter.dotfiles_url.value : null
    GIT_AUTHOR_NAME     = "${data.coder_workspace.me.owner}"
    GIT_COMMITTER_NAME  = "${data.coder_workspace.me.owner}"
    GIT_AUTHOR_EMAIL    = "${data.coder_workspace.me.owner_email}"
    GIT_COMMITTER_EMAIL = "${data.coder_workspace.me.owner_email}"
  }


  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }
}

data "coder_parameter" "custom_repo_url" {
  name         = "custom_repo"
  display_name = "Repository URL (custom)"
  order        = 5
  default      = ""
  description  = "Optionally enter a custom repository URL, see [awesome-devcontainers](https://github.com/manekinekko/awesome-devcontainers)."
  mutable      = true
}
data "coder_parameter" "dotfiles_url" {
  name        = "Dotfiles URL (optional)"
  description = "Personalize your workspace e.g., https://github.com/sharkymark/dotfiles.git"
  type        = "string"
  default     = ""
  mutable     = true 
  #icon        = "https://git-scm.com/images/logos/downloads/Git-Icon-1788C.png"
  order       = 6
}
data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository (auto)"
  order        = 5
  description  = "Select a repository to automatically clone and start working with a devcontainer."
  mutable      = true
  option {
    name        = "sharkymark/envbuilder-starter-devcontainer"
    description = "An example repository for getting started with devcontainer.json and envbuilder."
    value       = "https://github.com/sharkymark/envbuilder-starter-devcontainer"
   # icon        = "https://avatars.githubusercontent.com/u/95932066?s=200&v=4"
  }
  option {
    name        = "microsoft/vscode-remote-try-go"
    description = "Golang"
    value       = "https://github.com/microsoft/vscode-remote-try-go"
   # icon        = "https://cdn.worldvectorlogo.com/logos/golang-gopher.svg"
  }
  option {
    name        = "microsoft/vscode-remote-try-node"
    description = "Node.js"
    value       = "https://github.com/microsoft/vscode-remote-try-node"
   # icon        = "https://cdn.freebiesupply.com/logos/large/2x/nodejs-icon-logo-png-transparent.png"
  } 
  option {
    name        = "microsoft/vscode-remote-try-java"
    description = "Java"
    value       = "https://github.com/microsoft/vscode-remote-try-java"
   # icon        = "https://assets.stickpng.com/images/58480979cef1014c0b5e4901.png"
  }
  option {
    name        = "Custom"
    icon        = "/emojis/1f5c3.png"
    description = "Specify a custom repo URL below"
    value       = "custom"
  }
}
# code-server
resource "coder_app" "code-server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "code-server"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=/home/coder"
  subdomain    = false
  share        = "owner"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 3
    threshold = 10
  }
}
# VS Code Web
resource "coder_app" "vscode-web" {
  agent_id     = coder_agent.main.id
  slug         = "vscode-web"
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13338?folder=/home/coder"
  subdomain    = true  # VS Code Web does currently does not work with a subpath https://github.com/microsoft/vscode/issues/192947
  share        = "owner"
}


resource "kubernetes_persistent_volume_claim" "workspaces" {
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}-home"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-pvc"
      "app.kubernetes.io/instance" = "coder-pvc-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      //Coder-specific labels.
      "com.coder.resource"       = "true"
      "com.coder.workspace.id"   = data.coder_workspace.me.id
      "com.coder.workspace.name" = data.coder_workspace.me.name
      "com.coder.user.id"        = data.coder_workspace.me.owner_id
      "com.coder.user.username"  = data.coder_workspace.me.owner
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace.me.owner_email
    }
  }
  wait_until_bound = false
  spec {
    access_modes = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = "${data.coder_parameter.home_disk_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_deployment" "main" {
  count = data.coder_workspace.me.start_count
  depends_on = [
    kubernetes_persistent_volume_claim.workspaces
  ]
  wait_for_rollout = false
  metadata {
    name      = "coder-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
    namespace = var.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = "coder-workspace-${lower(data.coder_workspace.me.owner)}-${lower(data.coder_workspace.me.name)}"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace.me.owner_id
      "com.coder.user.username"    = data.coder_workspace.me.owner
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace.me.owner_email
    }
  }

  spec {
    # replicas = data.coder_workspace.me.start_count
    replicas = 1
    selector {
      match_labels = {
        "app.kubernetes.io/name" = "coder-workspace"
      }
    }
    strategy {
      type = "Recreate"
    }

    template {
      metadata {
        labels = {
          "app.kubernetes.io/name" = "coder-workspace"
        }
      }
      spec {
        security_context {
          run_as_user = 1000
          fs_group    = 1000
        }
        toleration {
          effect = "NoSchedule"
          key    = "sandbox.gke.io/runtime"
          operator = "Equal"
          value    = "gvisor"
        }

        container {
          name              = "dev"
          image             = data.coder_parameter.image.value
          image_pull_policy = "Always"
          command           = ["sh", "-c", coder_agent.main.init_script]
          security_context {
            run_as_user = "1000"
          }
          resources {
            requests = {
              "cpu"    = "250m"
              "memory" = "512Mi"
            }
            limits = {
              "cpu"    = "${data.coder_parameter.cpu.value}"
              "memory" = "${data.coder_parameter.memory.value}Gi"
            }
          }
 
          env {
            name  = "CODER_AGENT_TOKEN"
            value = coder_agent.main.token
          }
          env {
            name  = "GIT_URL"
            value = data.coder_parameter.repo.value == "custom" ? data.coder_parameter.custom_repo_url.value : data.coder_parameter.repo.value
          }                
          volume_mount {
            name       = "workspaces"
            mount_path = "/workspaces"
          }
        }
        volume {
          name = "workspaces"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim.workspaces.metadata.0.name
          }
        }



        affinity {
          // This affinity attempts to spread out all workspace pods evenly across
          // nodes.
          node_affinity {
            required_during_scheduling_ignored_during_execution {
              node_selector_term {
                  match_expressions {
                    key      = "node_pool"
                    operator = "In"
                    values   = ["user-pool"]
                }
              }
            }
          }
          pod_anti_affinity {
            preferred_during_scheduling_ignored_during_execution {
              weight = 1
              pod_affinity_term {
                topology_key = "kubernetes.io/hostname"
                label_selector {
                  match_expressions {
                    key      = "app.kubernetes.io/name"
                    operator = "In"
                    values   = ["coder-workspace"]
                  }
                }
              }
            }
          }
        }
      }
    }
  }
}
