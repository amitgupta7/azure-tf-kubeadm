#!/usr/bin/sh
set -x
while getopts r:k:s:t: flag
do
    case "${flag}" in
        r) region=${OPTARG};;
        k) apikey=${OPTARG};;
        s) apisecret=${OPTARG};;
        t) apitenant=${OPTARG};;        
    esac
done

install_epod(){
    kubectl kots install "securiti-scanner" --skip-preflights --license-file "license.yaml" --config-values "values.yaml" -n securiti --shared-password "securitiscanner" --wait-duration 10m --with-minio=false | tee scanner_install.log &

echo "If the above operation times out, update PVCs  ## storageClassName: longhorn, and run register_appliance.sh script"

cat <<EOF > register_appliance.sh
CONFIG_CTRL_POD=$(kubectl get pods -A -o jsonpath='{.items[?(@.metadata.labels.app=="priv-appliance-config-controller")].metadata.name}')
if [ -z "$CONFIG_CTRL_POD"]
then
  kubectl get pods -A
  echo "Config controller pod not found, please check the deployment"
  exit 1
fi


curl -s -X 'POST' \
  'https://app.securiti.ai/core/v1/admin/appliance' \
  -H 'accept: application/json' \
  -H 'X-API-Secret:  '$apisecret \
  -H 'X-API-Key:  '$apikey \
  -H 'X-TIDENT:  '$apitenant \
  -H 'Content-Type: application/json' \
  -d '{
  "owner": "amit.gupta@securiti.ai",
  "co_owners": [],
  "name": "localtest-'$(echo $RANDOM %10000+1 |bc)'",
  "desc": "",
  "send_notification": false
}' > sai_appliance.txt

SAI_LICENSE=$(cat sai_appliance.txt| jq -r '.data.license')
# get the pod name for the config controller pod, we'll need this for registration

# register with Securiti Cloud
kubectl exec -it "$CONFIG_CTRL_POD" -n "securiti" -- securitictl register -l "$SAI_LICENSE"
echo "Registered to appliance id: $(cat sai_appliance.txt| jq -r '.data.id')"
EOF
}

install_redis(){
    kubectl taint nodes --all node-role.kubernetes.io/master-
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml    
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add longhorn https://charts.longhorn.io
    ## storageClassName: longhorn
    helm repo update
    helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version 1.5.0

    REDIS_DEPLOYMENT_NAME=epod-ec
    helm install $REDIS_DEPLOYMENT_NAME --set master.persistence.storageClass=longhorn bitnami/redis 
    host=$REDIS_DEPLOYMENT_NAME-redis-master.default.svc.cluster.local
    password=$(kubectl get secret --namespace default $REDIS_DEPLOYMENT_NAME-redis -o jsonpath="{.data.redis-password}" | base64 -d)
    echo $host >> redis.host
    echo $password >> redis.pass    
    cat <<CONFIGVALS >values.yaml
apiVersion: kots.io/v1beta1
kind: ConfigValues
metadata:
  name: securiti-scanner
spec:
  values:
    redis_host:
        value: "$host"
    redis_password:
        value: "$password"
    use_redis_ssl:
        value: "0"
    region:
      value: $region
    install_dir:
       value: "/var/lib/"
CONFIGVALS
}
install_redis
