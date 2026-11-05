# Deploy Pulse – Infrastructure Notes

## Manually pushing an image to ECR and deploying to Kubernetes

Use these steps when you want to deploy a one-off build without going through
the Jenkins pipeline (e.g. a quick test on the cluster).

### 1. Authenticate Docker with ECR

```bash
aws ecr get-login-password --region ap-south-1 \
  | docker login --username AWS --password-stdin \
    <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com
```

### 2. Tag the local image

```bash
docker tag deploy-pulse:latest \
  <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/deploy-pulse:manual-1
```

### 3. Push the image to ECR

```bash
docker push \
  <ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/deploy-pulse:manual-1
```

### 4. Deploy to Kubernetes

The `k8s/deployment.yaml` file contains the literal string `IMAGE_PLACEHOLDER`
where the image name goes. Replace it on the fly with `sed` and pipe the result
straight to `kubectl apply` — this way the file on disk stays generic and no
real image URL is committed to the repo.

```bash
sed 's|IMAGE_PLACEHOLDER|<ACCOUNT_ID>.dkr.ecr.ap-south-1.amazonaws.com/deploy-pulse:manual-1|' \
  k8s/deployment.yaml | kubectl apply -f -
```

Apply the namespace and service the first time you set up the cluster (safe to
re-run on subsequent deploys):

```bash
kubectl apply -f k8s/namespace.yaml
kubectl apply -f k8s/service.yaml
```
