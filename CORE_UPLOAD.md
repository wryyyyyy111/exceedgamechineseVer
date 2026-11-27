# Core Upload Scope

本文件用于固定本项目“核心代码上传”范围，避免后续把大体积素材或临时文件误推送到远端仓库。

## 已上传基线

- 远端仓库：https://github.com/wryyyyyy111/exceedgamechineseVer
- 分支：main
- 基线提交：40048fe2c19afe2611778b53f81e6904104648f3

## 核心代码范围（已纳入版本控制）

- 根目录关键配置与说明：
  - .gitattributes
  - .gitignore
  - CORE_UPLOAD.md
  - README.md
  - project.godot
  - export_presets.cfg
  - runtests.cmd
- 核心逻辑与场景：
  - globals/
  - scenes/（已排除 .bak_* 备份文件）
- 数据与卡组定义：
  - data/
- 测试入口、公共测试基类与单元测试：
  - test/

## 默认不上传范围（按需另行评估）

- 美术与音频大资源：assets/
- 第三方或工具型目录：addons/、tools/、export_scripts/
- 平台构建与文档类：android/、docs/、documents/
- 本地开发配置与运行数据：.codex/、.github/、.vscode/、Godot/
- 其他素材：fonts/、根目录字体与图标文件
- 临时与备份：tmp/、*.bak_*、tmp_* 临时 smoke 文件、缓存与日志

## 忽略规则

- `.gitignore` 使用根目录白名单，仅保留上述核心目录和根目录配置文件。
- 核心目录内的备份、`tmp_*` 临时文件和缓存也会被忽略。
- 新增根目录文件或目录需要纳入版本控制时，应先更新白名单。
- 忽略规则不会自动取消暂存，也不会停止跟踪已提交的文件。
- 取消暂存使用 `git restore --staged -- 路径`，只修改暂存区，不删除本地文件；不要使用“放弃更改”代替。

## 后续增量上传建议流程

1. 查看改动：git status
2. 仅添加核心改动（示例）：
   - git add globals scenes data test project.godot
3. 检查暂存范围：git diff --cached --name-only
4. 提交：git commit -m "feat: 简要说明"
5. 推送：git push origin main

## 体量控制建议

- 每次提交前先过滤：
  - git diff --cached --name-only | findstr /R /C:"\\.bak_"
- 若误加文件，撤销暂存：
  - git restore --staged 路径
