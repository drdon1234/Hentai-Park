allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// 游戏 WebView 必须先绑定持久 Profile，再执行插件的 WebView 初始化。
// 仅替换构建目录中的插件源文件；上游结构变化时停止构建并重新核对。
subprojects {
    if (name == "flutter_inappwebview_android") {
        pluginManager.withPlugin("com.android.library") {
            val original = file("src/main/java/com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/FlutterWebView.java")
            val source = original.readText()
            val anchor = "    displayListenerProxy.onPostWebViewInitialization(displayManager);"
            val anchorAt = source.indexOf(anchor)
            require(anchorAt >= 0 && anchorAt == source.lastIndexOf(anchor) &&
                source.substring(0, anchorAt).trimEnd().endsWith(
                    "customSettings.useHybridComposition ? null : plugin.flutterView, userScripts);"
                )) {
                "WebView 创建流程已改变，请核对在线游戏 Profile 的绑定时序。"
            }
            val sourceDir = file("src/main/java")
            val treeNames = sourceDir.walkTopDown().filter { it.isFile }
                .map { it.relativeTo(sourceDir).invariantSeparatorsPath }.sorted().joinToString("\n")
            val treeHash = java.security.MessageDigest.getInstance("SHA-256")
                .digest(treeNames.toByteArray()).joinToString("") { "%02x".format(it) }
            val generated = layout.buildDirectory.dir("generated/park_webview_profile/$treeHash").get().asFile
            val replacement = """
    // Bind an explicitly marked game view before the plugin configures it.
    String parkGameProfile = null;
    boolean ambiguousParkGameProfile = false;
    for (UserScript script : userScripts) {
      String name = script.getGroupName();
      if (name != null && name.matches("park_game_[a-f0-9]{64}")) {
        if (parkGameProfile != null) ambiguousParkGameProfile = true;
        parkGameProfile = name;
      }
    }
    if (!ambiguousParkGameProfile && parkGameProfile != null &&
        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
      try {
        androidx.webkit.WebViewCompat.setProfile(webView, parkGameProfile);
      } catch (Exception ignored) {
        // Dart refuses to load the game unless the expected profile is bound.
      }
    }
""" + anchor
            val updated = source.replace(anchor, replacement)
            val prepareProfileSource = tasks.register("prepareParkGameWebView") {
                inputs.dir(sourceDir)
                outputs.dir(generated)
                doLast {
                    copy { from(sourceDir); into(generated) }
                    generated.resolve("com/pichillilorenzo/flutter_inappwebview_android/webview/in_app_webview/FlutterWebView.java")
                        .writeText(updated)
                }
            }
            tasks.matching { it.name == "preBuild" }.configureEach {
                dependsOn(prepareProfileSource)
            }
            extensions.getByType<com.android.build.api.dsl.LibraryExtension>()
                .sourceSets.getByName("main").java.apply {
                    directories.clear()
                    directories.add(generated.absolutePath)
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
