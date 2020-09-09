#!/bin/bash

#get openshift-install
oc adm release extract -a ${LOCAL_SECRET_JSON} --command=openshift-install "${LOCAL_REGISTRY}/${LOCAL_REPOSITORY}:${OCP_RELEASE}"

#if cloud.yaml setup already it will use it in this process
openshift-install create install-config --dir $HOME/openstack-upi

# create  manifests to tweak
openshift-install create manifests --dir $HOME/openstack-upi

# make master unschedulable, stop ingress controller from being on masters
ansible localhost -m lineinfile -a 'path="$HOME/openstack-upi/manifests/cluster-scheduler-02-config.yml" regexp="^  mastersSchedulable" line="  mastersSchedulable: false"'

pushd $HOME/openstack-upi

# we create these later for upi
rm -f openshift/99_openshift-cluster-api_master-machines-*.yaml

openshift-install create ignition-configs --dir $HOME/openstack-upi
ansible localhost -m lineinfile -a 'path=$HOME/.bashrc regexp="^export INFRA_ID" line="export INFRA_ID=$(jq -r .infraID $HOME/openstack-upi/metadata.json)"'
source $HOME/.bashrc

#adds dhcp-client to networkmanager
python3 $THIS_REPO/update_ignition.py

#check script results
jq '.storage.files | map(select(.path=="/etc/dhcp/dhclient.conf", .path=="/etc/NetworkManager/conf.d/dhcp-client.conf", .path=="/etc/dhcp/dhclient.conf", .path=="/etc/hostname"))' bootstrap.ign

#create ignition configs for masters
for index in $(seq 0 2); do
    MASTER_HOSTNAME="$INFRA_ID-master-$index\n"
    python3 -c "import base64, json, sys;
ignition = json.load(sys.stdin);
files = ignition['storage'].get('files', []);
files.append({'path': '/etc/hostname', 'mode': 420, 'contents': {'source': 'data:text/plain;charset=utf-8;base64,' + base64.standard_b64encode(b'$MASTER_HOSTNAME').decode().strip(), 'verification': {}}, 'filesystem': 'root'});
ignition['storage']['files'] = files;
json.dump(ignition, sys.stdout)" <master.ign >"$INFRA_ID-master-$index-ignition.json"
done

# bootstrap.ign put at some http endpoint, real bootstrap.ign to large for userdata this points to that endpoint
cat << EOF > $HOME/openstack-upi/$INFRA_ID-bootstrap-ignition.json
{
  "ignition": {
    "config": {
      "append": [
        {
          "source": "http://utilityvm.example.com/bootstrap.ign",
          "verification": {}
        }
      ]
    },
    "security": {},
    "timeouts": {},
    "version": "2.4.0"
  },
  "networkd": {},
  "passwd": {},
  "storage": {},
  "systemd": {}
}
EOF

#create api port
openstack port create --network "$GUID-ocp-network" \
  --security-group "$GUID-master_sg" \
  --fixed-ip "subnet=$GUID-ocp-subnet,ip-address=192.168.47.5" \
  --tag openshiftClusterID="$INFRA_ID" "$INFRA_ID-api-port" \
  -f json

#create ingress port
openstack port create \
  --network "$GUID-ocp-network" \
  --security-group "$GUID-worker_sg" \
  --fixed-ip "subnet=$GUID-ocp-subnet,ip-address=192.168.47.7" \
  --tag openshiftClusterID="$INFRA_ID" \
  "$INFRA_ID-ingress-port"

openstack floating ip set --port "$INFRA_ID-api-port" $API_FIP
openstack floating ip set --port "$INFRA_ID-ingress-port" $INGRESS_FIP

#create bootstrap port, .6 address is dns
openstack port create \
  --network "$GUID-ocp-network" \
  --security-group "$GUID-master_sg" \
  --allowed-address ip-address=192.168.47.5 \
  --allowed-address ip-address=192.168.47.6 \
  --allowed-address ip-address=192.168.47.7 \
  --tag openshiftClusterID="$INFRA_ID" \
  "$INFRA_ID-bootstrap-port"

# create bootstrap host, uses boostrap.ign created above
openstack server create --image rhcos-ocp45 --flavor 4c16g30d --user-data "$HOME/openstack-upi/$INFRA_ID-bootstrap-ignition.json" --port "$INFRA_ID-bootstrap-port" --wait --property openshiftClusterID="$INFRA_ID" "$INFRA_ID-bootstrap"

# create ports for masters
for index in $(seq 0 2); do
    openstack port create \
    --network "$GUID-ocp-network" \
    --security-group "$GUID-master_sg" \
    --allowed-address ip-address=192.168.47.5 \
    --allowed-address ip-address=192.168.47.6 \
    --allowed-address ip-address=192.168.47.7 \
    --tag openshiftClusterID="$INFRA_ID" \
    "$INFRA_ID-master-port-$index"
done

# create masters
for index in $(seq 0 2); do
    openstack server create \
    --boot-from-volume 30 \
    --image rhcos-ocp45 \
    --flavor 4c16g30d \
    --user-data "$HOME/openstack-upi/$INFRA_ID-master-$index-ignition.json" \
    --port "$INFRA_ID-master-port-$index" \
    --property openshiftClusterID="$INFRA_ID" \
    "$INFRA_ID-master-$index"
done

#wait for etcd to get up on masters and bootkube.service on bootstrap to complete
openstack server delete "$INFRA_ID-bootstrap"
openstack port delete "$INFRA_ID-bootstrap-port"

#admin creds
ansible localhost -m lineinfile -a 'path=$HOME/.bashrc regexp="^export KUBECONFIG" line="export KUBECONFIG=$HOME/openstack-upi/auth/kubeconfig"'
source $HOME/.bashrc

#show deployment progress
oc get clusterversion
oc get clusteroperators

## the following can be modifed as worker node requirements dictate
#create worker ports
for index in $(seq 0 1); do
    openstack port create \
    --network "$GUID-ocp-network" \
    --security-group "$GUID-worker_sg" \
    --allowed-address ip-address=192.168.47.5 \
    --allowed-address ip-address=192.168.47.6 \
    --allowed-address ip-address=192.168.47.7 \
    --tag openshiftClusterID="$INFRA_ID" \
    "$INFRA_ID-worker-port-$index"
done

# create workers
for index in $(seq 0 1); do
    openstack server create \
    --image rhcos-ocp45 \
    --flavor 4c16g30d \
    --user-data "$HOME/openstack-upi/worker.ign" \
    --port "$INFRA_ID-worker-port-$index" \
    --property openshiftClusterID="$INFRA_ID" \
    "$INFRA_ID-worker-$index"
done


