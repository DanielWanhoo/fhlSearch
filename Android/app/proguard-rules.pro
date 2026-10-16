# 忘川检索 混淆规则（当前 release 未开启 minify，保留文件以便将来启用）
# 应用不依赖反射访问自身类，题库数据以 JSON 放在 assets 中，无需额外 keep 规则。
-dontwarn kotlin.**
