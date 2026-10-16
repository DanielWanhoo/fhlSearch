// 根构建脚本：只声明插件版本，不在此处 apply。
// 版本组合经实测可用（本机只有 JDK 25，AGP 9.x 可在 JDK 25 下运行）。
// AGP 9.x 内置 Kotlin 支持，因此不需要再声明 org.jetbrains.kotlin.android。
plugins {
    id("com.android.application") version "9.4.1" apply false
}
