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
        versionCode = 1
        versionName = "1.0"
        resourceConfigurations += listOf("zh", "zh-rCN")
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

    testImplementation("junit:junit:4.13.2")
    // Android 自带的 org.json 在 JVM 单元测试里是空壳（方法会抛 not mocked），
    // 因此测试时用真实实现替换，这样测试跑的就是与 App 完全相同的解析代码。
    testImplementation("org.json:json:20240303")
}
