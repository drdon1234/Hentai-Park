import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter 插件位于 Android 插件之后。
    id("dev.flutter.flutter-gradle-plugin")
}

// 正式发布必须提供被 Git 忽略的 key.properties；CI 可明确选择无签名构建校验。
val verifyUnsignedBuild = providers.gradleProperty("verifyUnsignedBuild").orNull == "true"
val keystoreProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

gradle.taskGraph.whenReady {
    if (allTasks.any { it.name.contains("Release") } && !verifyUnsignedBuild) {
        require(listOf("storeFile", "storePassword", "keyAlias", "keyPassword").all {
            !keystoreProperties.getProperty(it).isNullOrBlank()
        }) { "正式发布需要完整的 android/key.properties；构建校验可显式使用 -PverifyUnsignedBuild=true（不生成可安装的发布包）" }
    }
}

android {
    namespace = "com.hentaipark.hentai_park"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.hentaipark.hentai_park"
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // 分 ABI 构建由 Flutter 自动调整 versionCode。
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystoreProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (verifyUnsignedBuild) null else signingConfigs.findByName("release")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Chromium WebView shape detection checks the host's GMS version metadata.
    // The library manifest supplies the official value, including on devices without GMS.
    implementation("com.google.android.gms:play-services-basement:18.4.0")
    implementation("androidx.webkit:webkit:1.14.0")
    implementation("androidx.media3:media3-extractor:1.9.2")
    implementation("androidx.media3:media3-muxer:1.9.2")
    // AppCompat themes are required by local_auth's biometric prompt (FlutterFragmentActivity).
    implementation("androidx.appcompat:appcompat:1.7.0")
}
