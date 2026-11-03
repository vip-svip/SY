                case "数据库监控": case "算法监控": case "Dex 查找与解析": case "内存快照":
                    showImportedSuitePendingPage(suite, category, page,
                            "该 Dia 开发监控功能尚未迁入；当前只登记原功能入口，不显示虚假运行状态。");
                    return;