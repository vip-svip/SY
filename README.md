# SY（KernelSU / Magisk 模块）


## 自检

```sh
sh tests/run_tests.sh all          # 引擎多轮自检（功能/幂等/作用域/启发式/性能/语法/健壮性）  92 项
sh tests/run_e2e.sh .              # 独立端到端验证（每类语法逐条推导期望值）              81 项
sh tests/run_module_checks.sh all  # 模块静态校验（语法/可移植性/清单/ABI/引用/面板/HTML/编码/链路/UI 运行时） 331 项
sh tests/run_module_checks.sh J    # 只跑面板资产回归 + jsdom 运行时 + Chromium 布局断言
sh tests/run_panel_api.sh          # 起真 abserver serve，逐端点打 HTTP（含鉴权 / 静态注入 / 多参数 POST）  29 项
sh tests/run_kernel_compat.sh      # 真 sing-box 内核双版本 check + run（1.11.15 / 1.14.3）  10 项
sh tests/run_route_e2e.sh          # 真流量验证四种规则命中 + Clash API 策略组切换              9 项
python tests/verify_ui_assets.py   # 面板资产回归（318 id / 225 action / 131 函数）
python tests/gen_preview.py        # 由 webroot/index.html 重新生成 ui-preview.html
node tests/ui_runtime_check.js     # jsdom 真实执行面板 JS，模拟导航交互
node tests/ui_shot_panel.js shots  # 真实 Chromium 逐页渲染线上面板并截图（注入 KSU 假数据）
python tests/perf_compare.py <序列号> "新面板=http://127.0.0.1:8848/index.html" \
                                  "旧面板=http://127.0.0.1:8849/index.html"   # 真机性能对比
sh package.sh                      # 打包并校验 ZIP（输出 dist/SY_<版本>.zip + .sha256）
```

> `run_module_checks.sh` 的 J 组会在检测到 jsdom / playwright 时自动启用真实 DOM 与真实浏览器断言
> （下拉是否被裁切、各视口是否横向溢出、实际启用背景模糊的元素数量）；未安装时自动跳过。


## 免责声明

本模块用于个人设备的学习与研究。请遵守当地法律法规及各应用服务条款。作者不对使用本模块产生的任何后果负责。
