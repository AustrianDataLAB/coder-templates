#!/bin/bash
sudo apt-get update
# install code-server
curl -fsSL https://code-server.dev/install.sh | sh
mkdir -p ~/work


if ! command -v az &> /dev/null; then
    curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash
    
else
    echo "AZ CLI is already installed."
fi

if ! command -v gcloud &> /dev/null; then
    curl https://sdk.cloud.google.com > install.sh
    bash install.sh --disable-prompts --install-dir=.
else
    echo "GCLOUD CLI is already installed."
fi


# add some Python libraries
pip3 install --user pandas &


if ! command -v nginx &> /dev/null; then
    sudo apt-get install -y nginx
else
    echo "Nginx is already installed."
fi
echo "${nginx_template_config_file}" | sudo tee /etc/nginx/sites-available/rstudio > /dev/null

# Enable the Nginx site
sudo ln -s /etc/nginx/sites-available/rstudio /etc/nginx/sites-enabled/

# Restart Nginx
sudo service nginx restart

# rstudio install

if ! command -v R &> /dev/null; then
    # sudo apt-get update
    sudo apt-get install -y r-base
else
    echo "R is already installed."
fi
if ! command -v gdebi &> /dev/null; then
    sudo apt-get install -y gdebi-core
else
    echo "gdebi-core is already installed."
fi
if [ ! -f rstudio-server-2023.03.1-446-amd64.deb ]; then
    wget https://download2.rstudio.org/server/bionic/amd64/rstudio-server-2023.03.1-446-amd64.deb
fi
sudo gdebi -n rstudio-server-2023.03.1-446-amd64.deb

# use coder CLI to clone and install dotfiles
coder dotfiles -y ${dotfiles_url} &

# setup ssh access to gitlab
if [ ! -f ~/.ssh/id_rsa ]; then
    UUID=$(cat /proc/sys/kernel/random/uuid)
    mkdir -p ~/.ssh
    ssh-keyscan -t ed25519 github.com >> ~/.ssh/known_hosts
    ssh-keyscan -t ed25519 $GITLAB_HOST >> ~/.ssh/known_hosts
    ssh-keygen -t rsa -b 4096 -f ~/.ssh/id_rsa -N ""
    eval `ssh-agent -s`
    ssh-add ~/.ssh/id_rsa
    # Add SSH key to GitLab
    curl --header "Authorization: Bearer $GITLAB_TOKEN" --request POST --form "title=$(hostname)-$UUID" --form "key=$(cat ~/.ssh/id_rsa.pub)" "https://$GITLAB_HOST/api/v4/user/keys"
    # getting a personal access token
    ssh git@$GITLAB_HOST personal_access_token coder-token-$HOSTNAME read_repository,write_repository,read_user,read_api,api 356 >> ~/.cache/personal_access_token.txt
    # Read the file and extract the token value
    GITLAB_WORKFLOW_TOKEN=$(grep -oP 'Token:\s+\K.+' ~/.cache/personal_access_token.txt)
    # Remove leading/trailing whitespace from the token value
    GITLAB_WORKFLOW_TOKEN=$(echo "$GITLAB_WORKFLOW_TOKEN" | tr -d '[:space:]')
    GITLAB_WORKFLOW_INSTANCE_URL=$(echo "https://$GITLAB_HOST")
    echo 'export GITLAB_WORKFLOW_INSTANCE_URL='$GITLAB_WORKFLOW_INSTANCE_URL >> ~/.bashrc
    echo 'export GITLAB_WORKFLOW_TOKEN='$GITLAB_WORKFLOW_TOKEN >> ~/.bashrc
else
    chmod 400 ~/.ssh/id_rsa
    eval `ssh-agent -s`
    ssh-add ~/.ssh/id_rsa
fi

# setup enviroment variable
source ~/.bashrc
git clone --progress git@github.com:sharkymark/pandas_automl.git &

# install VS Code extension
SERVICE_URL=https://open-vsx.org/vscode/gallery ITEM_URL=https://open-vsx.org/vscode/item code-server --install-extension ms-toolsai.jupyter
code-server --install-extension gitlab.gitlab-workflow

# change the starting point
cd ~/work

# setting up password for coder to connect to rstudio
# we can make this a variable tha get injected from interface but this work for now
echo 'coder:coder' | sudo chpasswd

# start services
code-server --auth none --port 13337 &
jupyter ${jupyter_type} --${jupyter_type_arg}App.token='' --ip='*' --${jupyter_type_arg}App.base_url=/@${owner_name}/${workspace_name}/apps/j &
sudo rstudio-server start --server-daemonize=1 --auth-none=1 &