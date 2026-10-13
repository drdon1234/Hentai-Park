package com.hentaipark.hentai_park

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import java.io.File

/** 只向系统安装器提供已验证的本应用更新包，系统仍要求用户确认。 */
class AppInstaller(private val activity: Activity) {
    fun openPermission() {
        if (Build.VERSION.SDK_INT >= 26) {
            activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")))
        }
    }

    @Suppress("DEPRECATION")
    fun install(path: String, version: String): Boolean {
        val root = File(activity.cacheDir, "app_updates").canonicalFile
        val apk = File(path).canonicalFile
        require(apk.path.startsWith(root.path + File.separator) && apk.isFile && apk.extension == "apk")
        val pm = activity.packageManager
        val flags = if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES
        val archive = pm.getPackageArchiveInfo(apk.path, flags) ?: error("INVALID_APK")
        val current = pm.getPackageInfo(activity.packageName, flags)
        require(archive.packageName == activity.packageName && archive.versionName == version)
        val newCode = if (Build.VERSION.SDK_INT >= 28) archive.longVersionCode else archive.versionCode.toLong()
        val oldCode = if (Build.VERSION.SDK_INT >= 28) current.longVersionCode else current.versionCode.toLong()
        require(newCode > oldCode)
        // 不允许未知签名的 APK 进入安装界面；系统会再次验证升级签名。
        val incoming = if (Build.VERSION.SDK_INT >= 28) archive.signingInfo?.apkContentsSigners else archive.signatures
        val installed = if (Build.VERSION.SDK_INT >= 28) current.signingInfo?.apkContentsSigners else current.signatures
        require(!incoming.isNullOrEmpty() && !installed.isNullOrEmpty() &&
            incoming.map { it.toCharsString() }.toSet() == installed.map { it.toCharsString() }.toSet())
        if (Build.VERSION.SDK_INT >= 26 && !pm.canRequestPackageInstalls()) return false
        val uri = FileProvider.getUriForFile(activity, "${activity.packageName}.updates", apk)
        activity.startActivity(Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        })
        return true
    }
}
