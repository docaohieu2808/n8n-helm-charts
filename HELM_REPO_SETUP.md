# Hướng dẫn Setup Helm Repository

Bạn đã package thành công n8n Helm chart! Bây giờ có 3 cách để tạo Helm repository:

## 📁 Files đã tạo

```
n8n/
├── n8n-helm-chart/           # Source code của Helm chart
│   ├── Chart.yaml
│   ├── values.yaml
│   ├── README.md
│   ├── templates/
│   └── charts/
└── n8n-1.0.0.tgz             # Packaged chart (đã build)
```

---

## Option 1: GitHub Pages (Khuyến nghị - Miễn phí & Đơn giản)

### Bước 1: Tạo GitHub Repository

```bash
# Tạo repo mới trên GitHub (ví dụ: n8n-helm-charts)
cd /home/hieudc/n8n
git init
git checkout -b main
```

### Bước 2: Tạo cấu trúc Helm repo

```bash
# Tạo thư mục charts
mkdir -p helm-repo/charts

# Copy packaged chart vào
cp n8n-1.0.0.tgz helm-repo/charts/

# Tạo index.yaml
helm repo index helm-repo/charts --url https://<username>.github.io/n8n-helm-charts/charts

# Tạo trang index.html
cat > helm-repo/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>n8n Helm Charts Repository</title>
    <style>
        body { font-family: Arial, sans-serif; max-width: 800px; margin: 50px auto; padding: 20px; }
        code { background: #f4f4f4; padding: 2px 6px; border-radius: 3px; }
        pre { background: #f4f4f4; padding: 15px; border-radius: 5px; overflow-x: auto; }
    </style>
</head>
<body>
    <h1>n8n Helm Charts Repository</h1>
    <p>Repository chứa Helm charts cho n8n workflow automation platform.</p>

    <h2>Cách sử dụng</h2>
    <pre><code># Add repository
helm repo add n8n https://&lt;username&gt;.github.io/n8n-helm-charts/charts
helm repo update

# Search charts
helm search repo n8n

# Install
helm install my-n8n n8n/n8n -n n8n --create-namespace

# Install với custom values
helm install my-n8n n8n/n8n -n n8n -f custom-values.yaml
</code></pre>

    <h2>Available Charts</h2>
    <ul>
        <li><strong>n8n</strong> - n8n workflow automation with separate webhook service (v1.0.0)</li>
    </ul>

    <h2>Source Code</h2>
    <p>Chart source: <a href="https://github.com/&lt;username&gt;/n8n-helm-charts">GitHub</a></p>
</body>
</html>
EOF
```

### Bước 3: Push lên GitHub

```bash
# Add files
git add .
git commit -m "Initial Helm repository setup"

# Add remote (thay <username> bằng GitHub username của bạn)
git remote add origin https://github.com/<username>/n8n-helm-charts.git
git push -u origin main
```

### Bước 4: Enable GitHub Pages

1. Vào GitHub repository settings
2. Chọn **Pages** (menu bên trái)
3. Source: chọn `main` branch và `/helm-repo` folder
4. Save

Sau vài phút, repo sẽ có tại: `https://<username>.github.io/n8n-helm-charts/charts`

### Bước 5: Sử dụng

```bash
# Add repository
helm repo add n8n https://<username>.github.io/n8n-helm-charts/charts
helm repo update

# Install
helm install my-n8n n8n/n8n -n n8n --create-namespace
```

### Cập nhật chart mới

```bash
# Package version mới
helm package n8n-helm-chart

# Copy vào charts folder
cp n8n-*.tgz helm-repo/charts/

# Re-index
helm repo index helm-repo/charts --url https://<username>.github.io/n8n-helm-charts/charts

# Commit và push
git add .
git commit -m "Update chart to version X.Y.Z"
git push
```

---

## Option 2: ChartMuseum (Self-hosted)

### Bước 1: Deploy ChartMuseum trong K8s

```bash
# Tạo namespace
kubectl create namespace chartmuseum

# Deploy ChartMuseum
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: chartmuseum
  namespace: chartmuseum
spec:
  replicas: 1
  selector:
    matchLabels:
      app: chartmuseum
  template:
    metadata:
      labels:
        app: chartmuseum
    spec:
      containers:
      - name: chartmuseum
        image: ghcr.io/helm/chartmuseum:v0.16.0
        ports:
        - containerPort: 8080
        env:
        - name: DISABLE_API
          value: "false"
        - name: ALLOW_OVERWRITE
          value: "true"
        - name: STORAGE
          value: "local"
        volumeMounts:
        - name: storage
          mountPath: /charts
      volumes:
      - name: storage
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: chartmuseum
  namespace: chartmuseum
spec:
  selector:
    app: chartmuseum
  ports:
  - port: 8080
    targetPort: 8080
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: chartmuseum
  namespace: chartmuseum
spec:
  ingressClassName: traefik-ingress
  rules:
  - host: charts.docaohieu.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: chartmuseum
            port:
              number: 8080
EOF
```

### Bước 2: Upload chart

```bash
# Upload chart bằng curl
curl --data-binary "@n8n-1.0.0.tgz" http://charts.docaohieu.com/api/charts

# Hoặc dùng helm plugin
helm plugin install https://github.com/chartmuseum/helm-push
helm cm-push n8n-1.0.0.tgz chartmuseum
```

### Bước 3: Sử dụng

```bash
# Add repository
helm repo add n8n http://charts.docaohieu.com
helm repo update

# Install
helm install my-n8n n8n/n8n -n n8n --create-namespace
```

---

## Option 3: OCI Registry (Harbor, Docker Hub, GitHub Container Registry)

### Sử dụng với GitHub Container Registry

```bash
# Login
echo $GITHUB_TOKEN | helm registry login ghcr.io -u <username> --password-stdin

# Push chart
helm push n8n-1.0.0.tgz oci://ghcr.io/<username>

# Install
helm install my-n8n oci://ghcr.io/<username>/n8n --version 1.0.0 -n n8n --create-namespace
```

### Sử dụng với Harbor

```bash
# Login
helm registry login harbor.docaohieu.com -u admin

# Push chart
helm push n8n-1.0.0.tgz oci://harbor.docaohieu.com/library

# Install
helm install my-n8n oci://harbor.docaohieu.com/library/n8n --version 1.0.0 -n n8n
```

---

## So sánh các phương pháp

| Phương pháp | Ưu điểm | Nhược điểm | Phù hợp với |
|-------------|---------|------------|-------------|
| **GitHub Pages** | ✅ Miễn phí<br>✅ Đơn giản<br>✅ Public | ❌ Chỉ public<br>❌ Manual update | Cá nhân, Open source |
| **ChartMuseum** | ✅ Self-hosted<br>✅ Private/Public<br>✅ API support | ❌ Cần infrastructure<br>❌ Phức tạp hơn | Team, Enterprise |
| **OCI Registry** | ✅ Modern approach<br>✅ Tích hợp với container registry<br>✅ Versioning tốt | ❌ Cần registry<br>❌ Ít phổ biến hơn | Modern setups |

---

## Kiểm tra Chart trước khi publish

```bash
# Validate chart
helm lint n8n-helm-chart

# Dry-run install
helm install my-n8n ./n8n-helm-chart --dry-run --debug -n n8n

# Template rendering
helm template my-n8n ./n8n-helm-chart -n n8n > output.yaml

# Install vào test namespace
helm install test-n8n ./n8n-helm-chart -n n8n-test --create-namespace

# Uninstall test
helm uninstall test-n8n -n n8n-test
```

---

## Best Practices

1. **Versioning**: Luôn tăng version trong `Chart.yaml` khi update
2. **Changelog**: Maintain CHANGELOG.md để track changes
3. **Testing**: Test chart trước khi publish
4. **Documentation**: Cập nhật README.md với mỗi version mới
5. **Security**: Không commit secrets vào git, use external secrets

---

## Khuyến nghị

Với setup hiện tại của bạn, tôi khuyến nghị:

1. **Ngắn hạn**: Dùng **GitHub Pages** - đơn giản, miễn phí, dễ bảo trì
2. **Dài hạn**: Nếu cần private charts hoặc CI/CD automation → **ChartMuseum** hoặc **Harbor**

Bắt đầu với GitHub Pages, sau đó migrate sang solution khác khi cần!
