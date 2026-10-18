package com.hentaipark.hentai_park

import android.app.Application

class ParkApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        NativeCrashLog.install(this)
    }
}
