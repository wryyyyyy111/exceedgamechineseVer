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
  - README.md
  - project.godot
  - export_presets.cfg
  - untests.cmd
- 核心逻辑与场景：
  - globals/
  - scenes/（已排除 .bak_* 备份文件）
- 数据与卡组定义：
  - data/
- 单元测试：
  - 	est/unit/

## 默认不上传范围（按需另行评估）

- 美术与音频大资源：assets/
- 第三方或工具型目录：addons/、	ools/、export_scripts/
- 平台构建与文档类：android/、docs/、documents/
- 临时与备份：	mp/、*.bak_*、临时 smoke 文件

## 后续增量上传建议流程

1. 查看改动：git status
2. 仅添加核心改动（示例）：
   - git add globals scenes/core scenes/game scenes/menu data test/unit project.godot
3. 检查暂存范围：git diff --cached --name-only
4. 提交：git commit -m "feat: 简要说明"
5. 推送：git push origin main

## 体量控制建议

- 每次提交前先过滤：
  - git diff --cached --name-only | findstr /R /C:"\\.bak_"
- 若误加文件，撤销暂存：
  - git restore --staged 路径
