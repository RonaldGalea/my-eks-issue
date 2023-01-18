Hello!

# Short summary of context and issue

I am using EFS to mount a PV (ReadWriteMany [access-mode](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)) via a PVC into EKS pods. The issue I'm having is that write updates propagate with big delays across pods: one pod may successfully write a file to the shared directory, but other pods see it some 10-60 seconds later (this delay varies across experiments seemingly at random).

## Experiment & Concrete results

I run two simple pods. [Pod1](debugging_pods/pod1.yaml) runs first and continuously checks if `/workdir/share_point/example.txt` exists via the `stat` command. [Pod2](debugging_pods/pod2.yaml) runs second and writes the file, then does the same checks. As can be seen from the logs below, the file created at `16:52:36.544` is visible in Pod1 only at ~`16:52:57.694`

Logs of Pod1: [pod1.log](logs/pod1.log)

Logs of Pod2: [pod2.log](logs/pod2.log)

## Expected results

I expected that Pod1 sees the file as soon as it is successfully written, as is the case for Pod2. As far as I understand, this would fit the [consistency](https://docs.aws.amazon.com/efs/latest/ug/how-it-works.html#consistency) model described in the docs.

## Worth Mentioning

If I manually `kubectl exec` into the pods and attempt something similar, the problem seems to not be there, see [manual_test.log](logs/manual_test.log)

1. Pod2: `echo "Manual test" > /workdir/share_point/manual_test.txt`
2. Pod1: `date +\"%T.%3N\" && stat /workdir/share_point/manual_test.txt`

## Steps to Reproduce

In what follows, I provide the simplest setup that reproduces the issue that I have. Following AWS docs, I set up a VPC, an EKS cluster and an EFS as a storage provider for the cluster. Each section below refers to the documentation I've followed and provides the commands used.

### VPC 

Follows [creating-a-vpc](https://docs.aws.amazon.com/eks/latest/userguide/creating-a-vpc.html). Creates a VPC from a template, will have 2 private and 2 public subnets with suitable configuration to host an EKS cluster.

```sh
aws cloudformation create-stack --stack-name public-private-subnets \
    --template-url https://s3.us-west-2.amazonaws.com/amazon-eks/cloudformation/2020-10-29/amazon-eks-vpc-private-subnets.yaml
```

### EKS cluster

Follows [create-cluster](https://docs.aws.amazon.com/eks/latest/userguide/create-cluster.html). I specify the cluster name, region, and for simplicity manually copy the subnet IDs of the above VPC.

```sh
eksctl create cluster --name my-demo-cluster --region eu-central-1 \
    --with-oidc --version 1.24 --node-ami-family Ubuntu2004 \
    --vpc-private-subnets private_subnet1_id,private_subnet2_id \
    --vpc-public-subnets public_subnet1_id,public_subnet2_id \
    --node-private-networking --managed
```

### EFS setup

Follows the [efs-csi-page](https://docs.aws.amazon.com/eks/latest/userguide/efs-csi.html)

<details><summary>Details</summary>
<p>

#### Create a Policy

`curl -O https://raw.githubusercontent.com/kubernetes-sigs/aws-efs-csi-driver/master/docs/iam-policy-example.json`

```sh
aws iam create-policy \
    --policy-name AmazonEKS_EFS_CSI_Driver_Policy \
    --policy-document file://iam-policy-example.json
```

#### Create a ServiceAccount

```sh
eksctl create iamserviceaccount \
    --cluster my-demo-cluster \
    --namespace kube-system \
    --name efs-csi-controller-sa \
    --attach-policy-arn arn:aws:iam::account-id:policy/AmazonEKS_EFS_CSI_Driver_Policy \
    --approve \
    --region eu-central-1
```

#### Install the EFS CSI Driver

```sh
helm repo add aws-efs-csi-driver https://kubernetes-sigs.github.io/aws-efs-csi-driver/
helm repo update
```

```sh
helm upgrade -i aws-efs-csi-driver aws-efs-csi-driver/aws-efs-csi-driver \
    --namespace kube-system \
    --set image.repository=602401143452.dkr.ecr.eu-central-1.amazonaws.com/eks/aws-efs-csi-driver \
    --set controller.serviceAccount.create=false \
    --set controller.serviceAccount.name=efs-csi-controller-sa
```

#### Creating the EFS, SG and mount points

For simplicity, manually copy the subnet IDs of the VPC.

`./complete_efs_setup.sh private_subnet1_id private_subnet2_id`

</p>
</details>

### Kubernetes StorageClass and PVC

Replace the Filesystem ID in `kubernetes_storage/efs-storageclass.yaml`:

`kubectl apply -f kubernetes_storage/efs-storageclass.yaml`

`kubectl apply -f kubernetes_storage/efs-pvc.yaml`

### Deploy pods

`kubectl apply -f debugging_pods/pod1.yaml`

After the first one is running:

`kubectl apply -f debugging_pods/pod2.yaml`

### Exec in pods

`kubectl exec --stdin --tty pod1 -- /bin/bash`

`kubectl exec --stdin --tty pod2 -- /bin/bash`


### Relevant system information

<details><summary>Output of `aws --version`:</summary>
<p>

```
aws-cli/2.8.7 Python/3.9.11 Linux/5.15.0-58-generic exe/x86_64.ubuntu.22 prompt/off
```

</p>
</details>


<details><summary>Output of `eksctl version`:</summary>
<p>

```
0.125.0
```

</p>
</details>

<details><summary>Output of `helm version`:</summary>
<p>

```
version.BuildInfo{Version:"v3.10.3", GitCommit:"835b7334cfe2e5e27870ab3ed4135f136eecc704", GitTreeState:"clean", GoVersion:"go1.18.9"}
```

</p>
</details>