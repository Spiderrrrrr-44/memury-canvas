# 决策日志

- 采用 Canvas 原生功能分支，以 RootAccount Feature Flag 隔离影响；原型明确不冒充官方功能。
- MVP 用用户级 JSONB 聚合持久化，优先保障完整闭环与刷新保留；生产化前应将高频 Evidence/Session/DecisionLog 拆表并配置保留策略。
- 排序和掌握度更新均为集中、确定性规则，不使用随机数，也不伪装成强化学习。
- 无外部模型时默认可靠 Demo；当前已加入服务器端 Responses API 兼容教学诊断服务，失败则自动回退到规则引擎。生产 LTI/OAuth、Blackboard 或 PeopleSoft 接入仍待后续扩展。
- 日历 MVP 采用可靠按钮操作；时间/时长重排 API 已保留，后续补编辑弹窗与冲突可视化。
- 当前 Windows 主机无 Docker、Ruby、Bundler、Yarn，无法在本机启动完整 Canvas；最短恢复路径是在 Canvas 官方 Docker 环境运行迁移、seed、定向 RSpec 与前端测试。

## 已知限制

Demo SIS 为固定相对时间数据；Page/Module、Calendar/Planner、教师反馈的真实 Connector 映射尚未覆盖。UI 已完成核心纵向闭环，但完整生产可访问性走查、浏览器 E2E 和真实模型 schema 校验留待下一轮。
