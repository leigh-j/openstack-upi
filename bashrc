export GUID=9b4a
export CLOUDUSER=cloud-user
export API_FIP=52.116.95.138
export INGRESS_FIP=52.116.95.18
export OPENSHIFT_DNS_ZONE=blue.osp.opentlc.com
export OS_CLOUD=9b4a-project
export OCP_RELEASE=4.5.8
export REGISTRY_AUTH_FILE=~/.podauth
export LOCAL_SECRET_JSON=~/.podauth
export LOCAL_REGISTRY=utilityvm.example.com:5000
export LOCAL_REPOSITORY=ocp-release/release
export ARCHITECTURE=x86_64
export REGISTRY_ADMIN_TOKEN=$(oc sa get-token -n openshift-config registry-admin)
export INFRA_ID=$(jq -r .infraID $HOME/openstack-upi/metadata.json)
export KUBECONFIG=$HOME/openstack-upi/auth/kubeconfig
export API_HOSTNAME=api.cluster-9b4a.blue.osp.opentlc.com
export INGRESS_DOMAIN=apps.cluster-9b4a.blue.osp.opentlc.com

