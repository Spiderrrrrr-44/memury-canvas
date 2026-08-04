# Memury 学脉 — Canvas-first MVP

Memury 是嵌入 Canvas 的目标感知自适应学习 Agent 原型。它只读取当前登录学生有权访问的 Canvas 课程与作业，将其与明确标注的模拟 SIS 事件合并，生成可执行学习块，并用可追溯证据驱动诊断、干预和计划重排。它不是 Instructure 官方功能，也不会写入正式成绩。

本改动继续遵循仓库原有 AGPLv3 许可证与版权声明；Canvas 与 Instructure 名称归其各自权利人所有。

## 启动

本分支遵循 Canvas 原有 Docker 开发方式：

```bash
cp .env.memury.example .env.memury
docker compose up -d
docker compose run --rm web bundle exec rails db:migrate
docker compose run --rm -e LOGIN=memury.student@example.test web bundle exec rake memury:demo_seed
yarn build:watch
```

先按 Canvas Quick Start 创建 `memury.student@example.test` 学生并让其加入课程；seed 是幂等的，会重置该用户的 Memury 演示状态且不会创建重复课程数据。登录后从全局导航进入“Memury 学脉”。若使用其他登录名，设置 `LOGIN`。

## 配置与能力

- `MEMURY_DEMO_MODE=true`（默认）：不需要外部 API Key，使用规则引擎、模拟 SIS 与预置题目。
- RootAccount Feature Flag `memury` 控制入口和路由。
- “立即同步”读取当前学生的活跃课程、已发布且有截止日期的作业以及本人的提交摘要。
- 学习块支持完成、跳过；诊断闭环包含候选错因、最小验证、渐进提示、迁移题、证据更新与重排。
- 状态存于 `memury_learner_profiles.state`，刷新页面后保留。

当前 Demo seed 以内部、非隐私数据展示两门课程、五项任务、三天后的考试和工程力学案例；真实 Canvas 课程数据达到五项任务时会替换演示任务列表。Demo 模式及模拟来源会在 UI 中持续标注。
