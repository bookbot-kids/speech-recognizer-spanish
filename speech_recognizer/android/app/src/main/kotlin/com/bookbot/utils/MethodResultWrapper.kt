/*
Copyright 2025 [BOOKBOT](https://bookbotkids.com/)

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
*/

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