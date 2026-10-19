import java.util.Properties

plugins {
    // 注意：AGP 9.x 起内置 Kotlin 支持，不能再单独 apply org.jetbrains.kotlin.android，
    // 否则报 "The 'org.jetbrains.kotlin.android' plugin is no longer required for Kotlin support since AGP 9.0"。
    id("com.android.application")
}

// release 签名：从 keystore.properties 读取；文件不存在则 release 产物不签名（但依然能编译出 apk）。
val keystorePropsFile = rootProject.file("keystore.properties")
val keystoreProps = Properties().apply {
    if (keystorePropsFile.exists()) keystorePropsFile.inputStream().use { load(it) }
}
val releaseStoreFile = keystoreProps.getProperty("storeFile")?.let { rootProject.file(it) }
val hasReleaseKeystore = releaseStoreFile?.exists() == true

android {
    namespace = "com.wangchuan.fhlsearch"

    // 本机 SDK 只装了 platforms/android-37.0，故 compileSdk = 37（不影响最低支持 Android 10）
    compileSdk = 37

    defaultConfig {
        applicationId = "com.wangchuan.fhlsearch"
        minSdk = 29          // 需求硬指标：Android 10
        targetSdk = 37
        versionCode = 3
        versionName = "3.0"
        resourceConfigurations += listOf("zh", "zh-rCN")

        // 只打这三种 ABI 的 .so。ML Kit 的中文识别库每个 ABI 都有 10 MB 上下：
        //   arm64-v8a    现在的手机 / 平板基本都是它
        //   armeabi-v7a  老一些的 32 位设备
        //   x86_64       模拟器（保留它才能用正式包在模拟器上验收）
        // 32 位 x86 早就没人用了，砍掉能省 11 MB。
        ndk {
            abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
        }
    }

    if (hasReleaseKeystore) {
        signingConfigs {
            create("release") {
                storeFile = releaseStoreFile
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
            if (hasReleaseKeystore) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        viewBinding = true
    }

    // 单元测试跑在 JVM 上：中文断言信息需要用 UTF-8 输出，否则控制台乱码
    testOptions {
        unitTests.all {
            it.systemProperty("file.encoding", "UTF-8")
            it.defaultCharacterEncoding = "UTF-8"
        }
    }

    packaging {
        resources.excludes += setOf("META-INF/*.kotlin_module")
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.19.1")
    implementation("androidx.appcompat:appcompat:1.8.0")
    implementation("com.google.android.material:material:1.14.0")
    implementation("androidx.constraintlayout:constraintlayout:2.2.1")
    implementation("androidx.fragment:fragment-ktx:1.9.0")
    implementation("androidx.recyclerview:recyclerview:1.4.0")
    implementation("androidx.viewpager2:viewpager2:1.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")

    // 诗词检索的「图片识别」：ML Kit 中文文字识别（**内置模型**版，不是 play-services 版）。
    // 内置版的模型跟 apk 一起装，不依赖 Google Play 服务、也不需要联网下载模型 ——
    // 国产手机通常没有 GMS，用 play-services 版会直接不可用；而这个 App 全程离线。
    implementation("com.google.mlkit:text-recognition-chinese:16.0.1")
    // 读相机/相册照片的 EXIF 方向（照片常常"躺着"存，不摆正字格检测必失败）
    implementation("androidx.exifinterface:exifinterface:1.4.1")

    testImplementation("junit:junit:4.13.2")
    // Android 自带的 org.json 在 JVM 单元测试里是空壳（方法会抛 not mocked），
    // 因此测试时用真实实现替换，这样测试跑的就是与 App 完全相同的解析代码。
    testImplementation("org.json:json:20240303")
}
