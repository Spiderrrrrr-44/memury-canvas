# Memury Canvas 升级套件（2026-08-16）

这不是独立 Demo 站。它把 Memury 的 Rails 接口、数据表、Canvas 页面入口和真实前端 bundle 安装到现有 `canvas.memury.net`。

## 部署内容

- Canvas 原生 `/memury`、`/memury/learn/:assignment_id` 等路由。
- 真实 `/memury/state`、同步、计划、Learning Graph 和分支追问接口。
- 3 组 additive 数据库迁移，不修改 Canvas 成绩表。
- Canvas Dashboard、课程页、作业页与全局导航入口。
- Canvas-first 产品界面；不再修改 Canvas 全局主题。
- 界面语言跟随 Canvas 用户语言偏好，支持中文与英文。
- 文档可直接用 Q Graph 打开，进行持久化多轮对话并生成整段对话总结。
- Q Graph 与 Memury 主界面统一采用 Apple 风格的浅色视觉系统。
- Demo 学生及课程种子，用于部署后立即验收。

## 安全边界

- 构建前对 Canvas 核心补丁执行零 fuzz dry-run；基础镜像不兼容时直接失败，不会半部署。
- 切换前备份 compose、容器元数据和 PostgreSQL volume。
- 数据库迁移只新增 `memury_*` 表。
- 回滚默认只切回原镜像并保留新增表；完整数据库归档也会保留。

## 服务器恢复后的执行顺序

```bash
mkdir -p /opt/memury-releases
tar -xzf memury-canvas-upgrade-20260816.tar.gz -C /opt/memury-releases
cd /opt/memury-releases/memury-canvas-20260816
sha256sum -c SHA256SUMS
chmod +x scripts/*.sh
./scripts/deploy.sh
./scripts/set-demo-password.sh
```

部署成功后访问：

```text
https://canvas.memury.net/login
https://canvas.memury.net/memury
```

公开 Demo 账号：

```text
账号：memury.student@example.test
密码：M3mury!cV8#qL2@pR7z
```

这个密码只用于隔离的 Demo 学生账号，故意公开以便直接验收。不要复用到真实 Canvas、邮箱、LMS 或管理员账号。全新部署执行 `./scripts/set-demo-password.sh` 时，请输入上面的 Demo 密码。

回滚：

```bash
./scripts/rollback.sh
```
