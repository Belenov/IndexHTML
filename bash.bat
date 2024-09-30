#!/bin/bash
set -e

K8S_VERSION=v1.29.3
CERT_MANAGER_VERSION=v1.14.4

BASE_URL="https://get.stopphish.ru"
RELEASE_MANIFEST="${BASE_URL}/packages/core/latest/manifest"

DIALOG=whiptail

if [ "$EUID" -ne 0 ]; then
  echo "Must be executed as root"
  exit
fi

if ! ($DIALOG --clear --title "StopPhish | Installation" --no-button "Cancel" --yesno "Proceed with installation?\n\nStopPhish will be installed to the current directory." 10 60 ); then
    exit;
fi

# Проверка наличия kubectl
if ! command -v kubectl &> /dev/null; then
    echo "kubectl не найден."
    exit 1
fi

echo "Установка Cert-Manager"
kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/v${CERT_MANAGER_VERSION}/cert-manager.yaml"

if [[ $(kubectl get cm -n stopphish stopphish-db --ignore-not-found) ]]; then
  echo "Backing up existing database configuration"
  kubectl get cm -n stopphish stopphish-db -o yaml > "$(date "+%Y-%m-%d_%H-%M-%S")-stopphish-db.yaml"
fi

if [[ ! -f stopphish.yaml ]]; then
  curl -s "$RELEASE_MANIFEST" -o stopphish.yaml
  sed -i "s|JWT_SECRET: \"stopphish\"|JWT_SECRET: \"$(< /dev/urandom tr -dc A-Za-z0-9 | head -c32)\"|" stopphish.yaml
  sed -i "s|DB_PASSWORD: \"stopphish\"|DB_PASSWORD: \"$(< /dev/urandom tr -dc A-Za-z0-9 | head -c32)\"|" stopphish.yaml
  sed -i "s|postgres:13.4|postgres:16-alpine|" stopphish.yaml
else 
  echo "Warning: stopphish.yaml already exists, skipping download! If you want a clean installation, please remove the file and run the script again."
fi

if [[ $(kubectl get ns stopphish --ignore-not-found) ]]; then
  echo "Stopphish namespace already exists, skipping"
else
  echo "Creating stopphish namespace"
  kubectl create ns stopphish
fi

kubectl apply -n stopphish -f stopphish.yaml

echo "StopPhish data will be located at: /srv/stopphish"
echo "Downloading StopPhish ... (May take up to several minutes)"
kubectl wait --for=condition=available --timeout=5m deployment -n stopphish api
kubectl wait --for=condition=available --timeout=5m deployment -n stopphish frontend

echo "Starting StopPhish ..."

$DIALOG --title "StopPhish | Congratulations" --msgbox "Installation complete! \n\nYou can now login to\n  $PUBLIC_URL \n  Login: admin@admin.com\n  Password: admin" 20 60

echo -e "\n\n+-------------------------------+\n|     Installation complete!    |\n+-------------------------------+\n"
echo -e "You can now login to:\n  URL :  http://localhost:80 \n  User:  admin@admin.com\n  Pass:  admin\n"

echo -e "* You may now exit the console. *\n"
