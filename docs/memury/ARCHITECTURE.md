# Memury 架构

## 数据流

`当前 Canvas 用户 → CanvasNativeConnector → 统一 provenance DTO → PriorityScorer → Study Blocks → React UI`

学习闭环为：`诊断错误 → 2–3 个候选错因 → 低成本验证题 → 分级提示 → 情境迁移题 → LearnerStateUpdater → 证据/决策日志 → 重排`。

## 边界

- Controller 只负责鉴权、状态机命令和 JSON 响应；核心规则位于 `app/services/memury`。
- `CanvasNativeConnector` 从当前用户的活跃 StudentEnrollment 出发，不接受任意 user/course id；作业、提交与成绩只读。
- `DemoSisConnector` 只生成明确标注的模拟课表/考试，不保存 SIS 凭据。
- 外部及推断数据统一携带 `source_platform`、`source_object_id`、`source_url`、`last_synced_at`、`official_or_inferred`、`confidence`。
- `Memury::LearnerProfile` 是 MVP 聚合根。JSONB 内含 Course/Goal/Learner/Intervention 四类状态及 LearningSession、StudyBlock、Evidence、DecisionLog 语义；后续可按规模拆表。

## 扩展

Connector 接口可替换为服务端 Canvas REST/LTI 1.3、Blackboard REST/LTI、OneRoster 或 PeopleSoft 实现；各实现必须返回相同 DTO 并在服务端执行授权。未来 `LearningAgentProvider` 应仅接收经过裁剪、当作不可信文本处理的课程上下文，并对结构化输出做 schema 校验；失败回退到现有确定性规则，密钥仅来自环境变量。当前实现已将这条路径落在 `Memury::Ai::TeachingDiagnosisService`，由 Rails 后端通过 Responses API 兼容接口完成教学诊断并在失败时自动回退。
