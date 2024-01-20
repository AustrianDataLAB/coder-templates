map \$http_upgrade \$connection_upgrade {
    default upgrade;
    ''      close;
  }
server {
    listen 7538;
    server_name localhost;

    location / {
      proxy_pass http://localhost:8787;
      proxy_redirect http://localhost:8787/ \$scheme://\$host/@${owner_name}/${workspace_name}/apps/rstudio/;
      proxy_http_version 1.1;
      proxy_set_header Upgrade \$http_upgrade;
      proxy_set_header Connection \$connection_upgrade;
      proxy_read_timeout 20d;
      # Use preferably
      proxy_set_header X-RStudio-Request \$scheme://\$host:\$server_port\$request_uri;
      # OR existing X-Forwarded headers
      proxy_set_header X-Forwarded-Host \$host;
      proxy_set_header X-Forwarded-Proto \$scheme;
      # OR alternatively the Forwarded header (just an example)
      proxy_set_header Forwarded \"host=\$host:\$server_port;proto=\$scheme;\";
    }
}