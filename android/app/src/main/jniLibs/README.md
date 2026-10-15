# 原应用内嵌的 API 运行库

各 ABI 目录中的 `libcpp.so` 来自原版文库 Android v1.30 应用的内嵌运行库，用于既有 `TokenManager.getMagicVersionCpp` JNI 入口。Flutter 工程原样复用，没有修改这些二进制。

它是联网接口的必要依赖，不能作为调试文件删除。对应 JNI 源码未包含在本工作区；公开分发前仍需核实该部分的对应源码与分发安排，见根目录 `docs/RELEASING.md`。
