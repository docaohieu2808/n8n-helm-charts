# Hướng dẫn Push lên GitHub với 2FA/Authenticator

Khi bật 2FA (Two-Factor Authentication) trên GitHub, bạn **KHÔNG THỂ** dùng password thông thường để push. Có 2 cách:

---

## ⭐ Cách 1: Personal Access Token (PAT) - Khuyến nghị cho HTTPS

### Bước 1: Tạo Personal Access Token trên GitHub

1. **Đăng nhập GitHub** → Click avatar (góc phải trên) → **Settings**

2. Kéo xuống menu trái → Click **Developer settings** (ở cuối cùng)

3. Click **Personal access tokens** → **Tokens (classic)**

4. Click **Generate new token** → **Generate new token (classic)**

5. Điền thông tin:
   - **Note**: `Helm Repository Access` (hoặc tên bạn muốn)
   - **Expiration**: Chọn thời gian hết hạn (khuyến nghị: 90 days hoặc 1 year)
   - **Select scopes**: Tích chọn:
     - ✅ `repo` (Full control of private repositories)
     - ✅ `write:packages` (nếu dùng GitHub Packages)
     - ✅ `read:packages`

6. Kéo xuống dưới → Click **Generate token**

7. **QUAN TRỌNG**: Copy token ngay (chỉ hiện 1 lần!)
   ```
   Ví dụ: ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

### Bước 2: Sử dụng Token để Push

#### Option A: Nhúng token vào URL (Nhanh nhưng kém bảo mật)

```bash
# Format: https://<token>@github.com/<username>/<repo>.git
git remote set-url origin https://ghp_YOUR_TOKEN_HERE@github.com/<username>/n8n-helm-charts.git

# Hoặc khi clone:
git clone https://ghp_YOUR_TOKEN_HERE@github.com/<username>/n8n-helm-charts.git
```

**Lưu ý**: Token sẽ lưu trong `.git/config` → Không nên dùng trên máy share

#### Option B: Lưu credential (Khuyến nghị)

```bash
# Cấu hình Git credential helper
git config --global credential.helper store

# Push lần đầu (sẽ hỏi username/password)
git push origin main

# Khi được hỏi:
# Username: <your-github-username>
# Password: <paste-your-token-here>  ← Dán PAT vào đây, KHÔNG phải password!

# Lần sau sẽ tự động dùng token đã lưu
```

Credential sẽ được lưu tại: `~/.git-credentials`

#### Option C: Dùng GitHub CLI (gh)

```bash
# Cài đặt gh (nếu chưa có)
# Ubuntu/Debian:
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
sudo apt update
sudo apt install gh

# Login
gh auth login
# → Chọn GitHub.com
# → Chọn HTTPS
# → Login bằng browser hoặc token

# Sau đó git push bình thường
git push origin main
```

---

## 🔑 Cách 2: SSH Keys - Khuyến nghị cho bảo mật cao

### Bước 1: Kiểm tra SSH key hiện có

```bash
ls -la ~/.ssh
# Nếu thấy id_rsa.pub hoặc id_ed25519.pub → đã có key
```

### Bước 2: Tạo SSH key mới (nếu chưa có)

```bash
# Tạo SSH key mới (khuyến nghị dùng ed25519)
ssh-keygen -t ed25519 -C "your-email@example.com"

# Hoặc dùng RSA (nếu hệ thống cũ):
ssh-keygen -t rsa -b 4096 -C "your-email@example.com"

# Nhấn Enter để lưu vào vị trí mặc định
# Nhập passphrase (hoặc bỏ trống nếu muốn)
```

### Bước 3: Copy public key

```bash
# Hiển thị public key
cat ~/.ssh/id_ed25519.pub
# hoặc
cat ~/.ssh/id_rsa.pub

# Copy toàn bộ output (bắt đầu với ssh-ed25519 hoặc ssh-rsa)
```

### Bước 4: Thêm SSH key vào GitHub

1. **GitHub** → Click avatar → **Settings**
2. Menu trái → **SSH and GPG keys**
3. Click **New SSH key**
4. Điền:
   - **Title**: `K8s Server` hoặc tên máy của bạn
   - **Key**: Paste public key đã copy
5. Click **Add SSH key**
6. Xác nhận bằng password GitHub (và 2FA code)

### Bước 5: Test SSH connection

```bash
ssh -T git@github.com

# Nếu thành công sẽ thấy:
# Hi <username>! You've successfully authenticated, but GitHub does not provide shell access.
```

### Bước 6: Đổi remote URL sang SSH

```bash
# Kiểm tra remote hiện tại
git remote -v

# Đổi từ HTTPS sang SSH
git remote set-url origin git@github.com:<username>/n8n-helm-charts.git

# Hoặc khi clone mới:
git clone git@github.com:<username>/n8n-helm-charts.git
```

### Bước 7: Push (không cần username/password)

```bash
git push origin main
# Không hỏi username/password nữa!
```

---

## 🚀 Setup Git Repository cho Helm Charts (Hoàn chỉnh)

```bash
cd /home/hieudc/n8n

# 1. Khởi tạo git (nếu chưa có)
git init
git checkout -b main

# 2. Tạo .gitignore
cat > .gitignore << 'EOF'
# OS files
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/

# Backup files
*.backup
*-backup-*.yaml

# Build output
*.tgz
!helm-repo/charts/*.tgz
EOF

# 3. Tạo cấu trúc Helm repo
mkdir -p helm-repo/charts

# 4. Copy chart đã package
cp n8n-1.0.0.tgz helm-repo/charts/

# 5. Tạo index (thay YOUR_USERNAME)
helm repo index helm-repo/charts --url https://YOUR_USERNAME.github.io/n8n-helm-charts/charts

# 6. Tạo homepage
cat > helm-repo/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>n8n Helm Charts</title>
    <meta charset="utf-8">
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
            max-width: 900px;
            margin: 50px auto;
            padding: 20px;
            line-height: 1.6;
        }
        code {
            background: #f4f4f4;
            padding: 2px 8px;
            border-radius: 4px;
            font-family: 'Courier New', monospace;
        }
        pre {
            background: #282c34;
            color: #abb2bf;
            padding: 20px;
            border-radius: 8px;
            overflow-x: auto;
            border-left: 4px solid #61afef;
        }
        pre code {
            background: none;
            color: inherit;
            padding: 0;
        }
        h1 { color: #333; border-bottom: 3px solid #61afef; padding-bottom: 10px; }
        h2 { color: #555; margin-top: 30px; }
        .badge {
            background: #61afef;
            color: white;
            padding: 4px 10px;
            border-radius: 12px;
            font-size: 12px;
            font-weight: bold;
        }
        a { color: #61afef; text-decoration: none; }
        a:hover { text-decoration: underline; }
        ul { padding-left: 20px; }
        li { margin: 8px 0; }
    </style>
</head>
<body>
    <h1>🚀 n8n Helm Charts Repository</h1>
    <p>
        <span class="badge">v1.0.0</span>
        Helm charts for deploying n8n workflow automation platform with production-ready architecture.
    </p>

    <h2>📦 Quick Start</h2>
    <pre><code># Add repository
helm repo add n8n https://YOUR_USERNAME.github.io/n8n-helm-charts/charts
helm repo update

# Search available charts
helm search repo n8n

# Install n8n
helm install my-n8n n8n/n8n -n n8n --create-namespace

# Install with custom values
helm install my-n8n n8n/n8n -n n8n -f custom-values.yaml
</code></pre>

    <h2>✨ Features</h2>
    <ul>
        <li>✅ Separate webhook service for high-performance webhook handling</li>
        <li>✅ Horizontal Pod Autoscaling (HPA) for webhook and worker pods</li>
        <li>✅ PostgreSQL HA support</li>
        <li>✅ Redis HA for queue and cache</li>
        <li>✅ Persistent storage with configurable storage class</li>
        <li>✅ Pod anti-affinity for high availability</li>
        <li>✅ Comprehensive health checks</li>
        <li>✅ Prometheus metrics support</li>
    </ul>

    <h2>📋 Available Charts</h2>
    <table style="width:100%; border-collapse: collapse;">
        <tr style="background: #f4f4f4;">
            <th style="padding: 10px; text-align: left; border-bottom: 2px solid #ddd;">Chart</th>
            <th style="padding: 10px; text-align: left; border-bottom: 2px solid #ddd;">Version</th>
            <th style="padding: 10px; text-align: left; border-bottom: 2px solid #ddd;">App Version</th>
            <th style="padding: 10px; text-align: left; border-bottom: 2px solid #ddd;">Description</th>
        </tr>
        <tr>
            <td style="padding: 10px; border-bottom: 1px solid #ddd;"><strong>n8n</strong></td>
            <td style="padding: 10px; border-bottom: 1px solid #ddd;"><code>1.0.0</code></td>
            <td style="padding: 10px; border-bottom: 1px solid #ddd;"><code>1.117.3</code></td>
            <td style="padding: 10px; border-bottom: 1px solid #ddd;">Workflow automation with separate webhook service</td>
        </tr>
    </table>

    <h2>📖 Documentation</h2>
    <ul>
        <li><a href="https://github.com/YOUR_USERNAME/n8n-helm-charts">GitHub Repository</a></li>
        <li><a href="https://docs.n8n.io/">n8n Official Documentation</a></li>
    </ul>

    <h2>⚙️ Configuration</h2>
    <p>Create a <code>custom-values.yaml</code> file:</p>
    <pre><code>config:
  host: "n8n.example.com"
  webhookUrl: "https://n8n.example.com"

webhook:
  autoscaling:
    minReplicas: 4
    maxReplicas: 20

secrets:
  postgresPassword: "your-secure-password"
  encryptionKey: "your-encryption-key"
</code></pre>

    <h2>🔒 Security</h2>
    <p><strong>⚠️ Important:</strong> Change default secrets in production!</p>
    <pre><code># Generate secure keys
openssl rand -hex 32  # For encryption key
openssl rand -base64 32  # For passwords
</code></pre>

    <footer style="margin-top: 50px; padding-top: 20px; border-top: 1px solid #ddd; color: #888; text-align: center;">
        <p>Maintained by YOUR_USERNAME | Licensed under Sustainable Use License</p>
    </footer>
</body>
</html>
EOF

# 7. Tạo README.md cho repo
cat > README.md << 'EOF'
# n8n Helm Charts Repository

Production-ready Helm charts for deploying n8n workflow automation platform on Kubernetes.

## Features

- ✅ Separate webhook service for optimal scalability
- ✅ Auto-scaling for webhook and worker pods
- ✅ PostgreSQL HA and Redis HA support
- ✅ Persistent storage
- ✅ High availability with pod anti-affinity
- ✅ Comprehensive health checks
- ✅ Prometheus metrics

## Usage

```bash
# Add repository
helm repo add n8n https://YOUR_USERNAME.github.io/n8n-helm-charts/charts
helm repo update

# Install
helm install my-n8n n8n/n8n -n n8n --create-namespace
```

## Charts

| Chart | Version | App Version | Description |
|-------|---------|-------------|-------------|
| n8n   | 1.0.0   | 1.117.3     | Workflow automation platform |

## Documentation

See [chart documentation](./n8n-helm-chart/README.md) for detailed configuration options.

## License

n8n is licensed under the [Sustainable Use License](https://github.com/n8n-io/n8n/blob/master/LICENSE.md).
EOF

# 8. Add files
git add .

# 9. Commit
git commit -m "Initial Helm repository with n8n chart v1.0.0"

# 10. Tạo repo trên GitHub (manual hoặc dùng gh CLI)
# Manual: Lên github.com → New repository → tên: n8n-helm-charts

# Hoặc dùng gh CLI:
gh repo create n8n-helm-charts --public --source=. --remote=origin --push

# 11. Nếu tạo manual, add remote và push:
# Thay YOUR_USERNAME bằng username GitHub của bạn

# Với HTTPS (dùng PAT):
git remote add origin https://github.com/YOUR_USERNAME/n8n-helm-charts.git

# HOẶC với SSH:
git remote add origin git@github.com:YOUR_USERNAME/n8n-helm-charts.git

# 12. Push
git push -u origin main
```

---

## 🌐 Enable GitHub Pages

1. Vào **repository settings** trên GitHub
2. Chọn **Pages** (menu trái)
3. **Source**:
   - Branch: `main`
   - Folder: `/helm-repo`
4. Click **Save**
5. Đợi vài phút → repo sẽ available tại: `https://YOUR_USERNAME.github.io/n8n-helm-charts/charts`

---

## ❌ Troubleshooting

### Lỗi: "remote: Support for password authentication was removed"

```bash
# ✅ Giải pháp: Dùng Personal Access Token thay vì password
# Khi git push hỏi password, paste PAT token vào
```

### Lỗi: "Permission denied (publickey)"

```bash
# ✅ Giải pháp: Thêm SSH key vào ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519

# Test connection
ssh -T git@github.com
```

### Token hết hạn

```bash
# Tạo token mới trên GitHub
# Update credential:
git config --global --unset credential.helper
git config --global credential.helper store
git push  # Nhập username và token mới
```

---

## 📝 Summary

### HTTPS với PAT (Dễ hơn):
1. Tạo PAT trên GitHub Settings
2. `git config --global credential.helper store`
3. `git push` → nhập username + PAT
4. Xong!

### SSH (Bảo mật hơn):
1. Tạo SSH key: `ssh-keygen -t ed25519`
2. Add public key vào GitHub Settings
3. `git remote set-url origin git@github.com:username/repo.git`
4. `git push` → không cần password!

**Khuyến nghị**: Dùng SSH cho lâu dài, PAT cho quick testing.
EOF
