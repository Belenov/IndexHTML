#!/bin/bash
set -e

CERT_MANAGER_VERSION=v1.14.4
BASE_URL="https://get.stopphish.ru"
RELEASE_MANIFEST="${BASE_URL}/packages/core/latest/manifest"
DIALOG=whiptail

if [ "$EUID" -ne 0 ]; then
  echo "Must be executed as root"
  exit
fi

if ! ($DIALOG --clear --title  "StopPhish | Installation" --no-button "Cancel" --yesno "Proceed with installation?\n\nStopphish will be installed to the current directory." 10 60 ); then
    exit;
fi

if ! command -v kubectl &> /dev/null; then
    echo "kubectl not found. Please install kubectl and ensure it is in your PATH."
    exit 1
fi

if ! kubectl version &> /dev/null; then
    echo "Unable to connect to Kubernetes cluster. Ensure kubeconfig is properly configured."
    exit 1
fi

if [[ ! -f /etc/kubernetes/registries.yaml ]]; then
  echo "Creating registries.yaml"
  mkdir -p /etc/kubernetes
  curl -s "$BASE_URL/mirror/registries.yaml" -o /etc/kubernetes/registries.yaml
else
  echo "Custom registry configuration already exists, skipping"
fi

if [[ $(kubectl get clusterrolebinding traefik-global-read --ignore-not-found) ]]; then
  echo "Traefik rolebinding already exists, skipping"
else
  echo "Creating traefik rolebinding"
  kubectl create clusterrolebinding --clusterrole=view --serviceaccount=kube-system:traefik traefik-global-read
fi

if [[ $(kubectl get crd certificates.cert-manager.io --ignore-not-found) ]]; then
  echo "Cert-manager already exists, skipping"
else
  echo "Installing cert-manager"
  kubectl apply -f "$BASE_URL/mirror/cert-manager/$CERT_MANAGER_VERSION/cert-manager.yaml"
fi

if [[ $(kubectl get cm -n stopphish stopphish-db --ignore-not-found) ]]; then
  echo "Backing up existing database configuration"
  kubectl get cm -n stopphish stopphish-db -o yaml > $(date "+%Y-%m-%d_%H-%M-%S")-stopphish-db.yaml
fi

if [[ ! -f stopphish.yaml ]]; then
  curl -s "$RELEASE_MANIFEST" -o stopphish.yaml
  sed -i "s|JWT_SECRET: \"stopphish\"|JWT_SECRET: \"$(< /dev/urandom tr -dc A-Za-z0-9 | head -c32)\"|" stopphish.yaml
  sed -i "s|DB_PASSWORD: \"stopphish\"|DB_PASSWORD: \"$(< /dev/urandom tr -dc A-Za-z0-9 | head -c32)\"|" stopphish.yaml
  sed -i "s|postgres:13.4|postgres:16-alpine|" stopphish.yaml
else
  echo "Warning: stopphish.yaml already exists, skipping download! If you want a clean installation, please remove the file and run the script again."
fi

curl -s "$BASE_URL/traefik-config.yaml" -o traefik-config.yaml
kubectl apply -f traefik-config.yaml

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
