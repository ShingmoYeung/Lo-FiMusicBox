# 应用图标资源约定

本文档记录当前应用图标资源的使用方式。图标已经以 `assets/AppIcon.icns` 的形式定稿，打包时直接复制该文件，不再通过脚本从 PNG 生成或覆盖图标。

## 输入与输出

- 图标源文件：`assets/AppIcon.icns`。
- 归档备份：`docs/images/icon/AppIcon.icns`。
- 打包位置：`.app/Contents/Resources/AppIcon.icns`。
- `Info.plist` 通过 `CFBundleIconFile=AppIcon` 指向该图标。
- `scripts/build-app-icon.sh` 仅校验 `.icns` 文件存在、非空且可被 `iconutil` 解析，不生成、不转换、不覆盖图标。

## 替换图标

如果后续要更新应用图标：

1. 在外部设计或图标工具中产出最终 `.icns`。
2. 覆盖 `assets/AppIcon.icns`。
3. 同步覆盖 `docs/images/icon/AppIcon.icns`，保留一份文档归档备份。
4. 运行 `./scripts/build-app-icon.sh` 校验文件格式。
5. 运行 `./scripts/package-macos-app.sh` 重新打包。

## 打包约束

- `scripts/package-macos-app.sh` 不会调用任何图标生成流程。
- 如果 `assets/AppIcon.icns` 缺失、为空或不是有效 `.icns`，打包会直接失败。
- 每次打包前会清理 `.build/` 和 `dist/`，然后重新构建 `.app`、zip 和 dmg。
