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
kubectl kots install "securiti-scanner" --skip-preflights --license-file "license.yaml" --config-values "values.yaml" -n securiti --shared-password "securitiscanner" --wait-duration 10m --with-minio=false > securiti_epod_install.log 2>&1 &
sleep 30
kubectl delete pvc -n securiti kotsadm-rqlite-kotsadm-rqlite-0
kubectl apply -f kots-rqlite.yaml
sleep 30
kubectl get pvc -A
sleep 5m
CONFIG_CTRL_POD=$(kubectl get pods -A -o jsonpath='{.items[?(@.metadata.labels.app=="priv-appliance-config-controller")].metadata.name}')
if [[ -z "$CONFIG_CTRL_POD"]]; then
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
  "name": "localtest-'$(date +"%s")'",
  "desc": "",
  "send_notification": false
}' > sai_appliance.txt

SAI_LICENSE=$(cat sai_appliance.txt| jq -r '.data.license')
# get the pod name for the config controller pod, we'll need this for registration

# register with Securiti Cloud
kubectl exec -it "$CONFIG_CTRL_POD" -n "securiti" -- securitictl register -l "$SAI_LICENSE"
echo "Registered to appliance id: $(cat sai_appliance.txt| jq -r '.data.id')"
}

install_statefulsets(){
    kubectl taint nodes --all node-role.kubernetes.io/master-
    kubectl taint nodes --all node-role.kubernetes.io/control-plane-
    kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml    
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add longhorn https://charts.longhorn.io
    ## storageClassName: longhorn
    helm repo update
    helm install longhorn longhorn/longhorn --namespace longhorn-system --create-namespace --version 1.5.0

    REDIS_DEPLOYMENT_NAME=epod-ec
    POSTGRES_DEPLOYMENT_NAME=epod-pg
    ELASTICSEARCH_DEPLOYMENT_NAME=epod-es
    helm install $REDIS_DEPLOYMENT_NAME --set master.persistence.storageClass=longhorn bitnami/redis --version "16.13.2"
    helm install $POSTGRES_DEPLOYMENT_NAME --set persistence.storageClass=longhorn bitnami/postgresql --version "11.9.13"
    helm install $ELASTICSEARCH_DEPLOYMENT_NAME bitnami/elasticsearch --version "18.2.16"
    #helm install $REDIS_DEPLOYMENT_NAME --set master.persistence.storageClass=longhorn bitnami/redis 
    kubectl delete pvc redis-data-epod-ec-redis-replicas-0
    kubectl delete pvc data-epod-pg-postgresql-0
    kubectl apply -f redis-replica.yaml
    kubectl apply -f postgres-data.yml

    kubectl delete pvc data-epod-es-elasticsearch-data-0
    kubectl delete pvc data-epod-es-elasticsearch-data-1
    kubectl delete pvc data-epod-es-elasticsearch-master-0
    kubectl delete pvc data-epod-es-elasticsearch-master-1
    kubectl apply -f es-data0.yaml  
    kubectl apply -f es-data1.yaml  
    kubectl apply -f es-master0.yaml  
    kubectl apply -f es-master1.yaml

    ec_host=$REDIS_DEPLOYMENT_NAME-redis-master.default.svc.cluster.local
    ec_password=$(kubectl get secret --namespace default $REDIS_DEPLOYMENT_NAME-redis -o jsonpath="{.data.redis-password}" | base64 -d)  
    pg_password=$(kubectl get secret --namespace default $POSTGRES_DEPLOYMENT_NAME-postgresql -o jsonpath="{.data.postgres-password}" | base64 -d)
    pg_host=$POSTGRES_DEPLOYMENT_NAME-postgresql.default.svc.cluster.local
    es_host=$ELASTICSEARCH_DEPLOYMENT_NAME-elasticsearch.default.svc.cluster.local
    cat <<CONFIGVALS >values.yaml
apiVersion: kots.io/v1beta1
kind: ConfigValues
metadata:
  name: securiti-scanner
spec:
  values:
    redis_host:
        value: "$ec_host"
    redis_password:
        value: "$ec_password"
    use_redis_ssl:
        value: "0"
    region:
      value: $region
    install_dir:
       value: "/var/lib/"
    enable_external_postgres:
        value: "1"
    postgres_host:
        value: "$pg_host"
    postgres_password:
        value: "$pg_password"
    enable_external_es:
        value: "1"
    es_host:
        value: "$es_host"
CONFIGVALS
}
install_statefulsets
install_epod
