# azure-tf-kubeadm
This example setup up a vanilla kubernetes cluster using `kubeadm`, to test older versions of kubernetes with the securiti epod appliance installer. Since the epods installer can be used for online installation, only the kots license file 'license.yaml' file from securiti is needed to setup the appliance. 

## setup instructions

```bash
# Install terraform, az-cli and obtain 'license.yaml' for securiti kots based appliance.  
# clone this repo.
# set appropreate tfvar values
# run 
# tfaa to provision
# tfda to provision
# tfs list to list resources
# tfo to print output
```

The default script will setup two ubuntu nodes with 10.0.2.21 and 10.0.2.22 private_ip_address in westus2 azure region, running ubuntu server 20.04 lts os version. The default machine size is Standard_D8s_v3. These can be overridden using the following tfvar file.
```hcl
az_subscription_id = "your azure subscription id"
az_resource_group  = "existing resource group"
X_API_Secret="sai apisecret"
X_API_Key="sai apikey"
X_TIDENT="sai apitenant"
vm_map = {"pod1":{"private_ip_address":"10.0.2.21", "role":"master"}}
vm_size = "Standard_D32s_v3"
az_name_prefix="azure-tf-vms-yourname-here"
```