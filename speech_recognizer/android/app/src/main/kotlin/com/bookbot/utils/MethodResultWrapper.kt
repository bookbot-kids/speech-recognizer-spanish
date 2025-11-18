package com.bookbot.utils

import io.flutter.plugin.common.MethodChannel

class MethodResultWrapper(private val methodResult: MethodChannel.Result): MethodChannel.Result {
    private var hasSubmitted: Boolean

    init {
        hasSubmitted = false
    }

    override fun success(result: Any?) {
        if(!hasSubmitted) {
            hasSubmitted = true
            methodResult.success(result)
        }
    }

    override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
        if(!hasSubmitted) {
            hasSubmitted = true
            methodResult.error(errorCode, errorMessage, errorDetails)
        }
    }

    override fun notImplemented() {
        if(!hasSubmitted) {
            hasSubmitted = true
            methodResult.notImplemented()
        }
    }
}