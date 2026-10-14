@AGENTS.md

## 给 Claude 的补充

- 界面改动遵循 [docs/DESIGN.md](docs/DESIGN.md)；插件协议以 [docs/SOURCE_API.md](docs/SOURCE_API.md) 为准；构建、检查与数据语义见 [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md)。
- 项目技能：新增站点用 `add-source`，验证站点用 `verify-source`，发布前检查用 `release-check`。
- Flutter 不一定在 PATH 上，`tools/check.ps1` 可以用 `-FlutterCommand`、`-DartCommand` 传入完整路径。
