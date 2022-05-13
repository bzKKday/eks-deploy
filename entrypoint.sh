#!/bin/sh

set -e

cluster="$1"
region="$2"
role="$3"
command="$4"

version=$(curl -Ls https://dl.k8s.io/release/stable.txt)
echo "using kubectl@v1.23.6"

curl -sLO "https://dl.k8s.io/release/$version/bin/linux/amd64/kubectl" -o kubectl
chmod +x kubectl
mv kubectl /usr/local/bin

export AWS_DEFAULT_REGION=$region

# Fetch the token from the AWS account.
KUBERNETES_TOKEN=$(aws-iam-authenticator token -i $cluster -r $role | jq -r .status.token)

if [ -z $KUBERNETES_TOKEN ]; then
  echo "Unable to obtain Kubernetes token - check Drone's IAM permissions"
  echo "Maybe it cannot assume the $role role?"
  exit 1
fi

# Assume the deployer role and set AWS creds to get further cluster information
aws sts assume-role --role-arn $role --role-session-name "drone" > assume-role-output.json
export AWS_ACCESS_KEY_ID=$(cat assume-role-output.json | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(cat assume-role-output.json | jq -r .Credentials.SecretAccessKey)
export AWS_SESSION_TOKEN=$(cat assume-role-output.json | jq -r .Credentials.SessionToken)

# Fetch the EKS cluster information.
EKS_URL=$(aws eks describe-cluster --name $cluster | jq -r .cluster.endpoint)
EKS_CA=$(aws eks describe-cluster --name $cluster | jq -r .cluster.certificateAuthority.data)

if [ -z $EKS_URL ] || [ -z $EKS_CA ]; then
  echo "Unable to obtain EKS cluster information - check Drone's EKS API permissions"
  exit 1
fi

# restore environment by removing static keys
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN

# Generate configuration files
cat > /tmp/config << EOF
apiVersion: v1
preferences: {}
kind: Config
clusters:
- cluster:
    server: ${EKS_URL}
    certificate-authority-data: ${EKS_CA}
  name: eks_$cluster
contexts:
- context:
    cluster: eks_$cluster
    user: eks_$cluster
  name: eks_$cluster
current-context: eks_$cluster
users:
- name: eks_$cluster
  user:
    exec:
      apiVersion: client.authentication.k8s.io/v1alpha1
      command: aws-iam-authenticator
      interactiveMode: Never
      args:
        - "token"
        - "-i"
        - $cluster
        - -r
        - $role
EOF

export KUBECONFIG=/tmp/config
sh -c "kubectl $command"
