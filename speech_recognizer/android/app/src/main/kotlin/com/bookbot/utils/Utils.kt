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

import android.content.res.AssetManager
import java.io.File
import java.io.File.separator
import java.io.FileOutputStream
import java.io.IOException
import java.io.OutputStream

inline fun <T1 : Any, T2 : Any, R : Any> let2(p1: T1?, p2: T2?, block: (T1, T2) -> R?): R? {
    return if (p1 != null && p2 != null) block(p1, p2) else null
}

class Utils {
    companion object {
        fun AssetManager.copyAssetFolder(srcName: String, dstName: String): Boolean {
            return try {
                var result: Boolean
                val fileList = this.list(srcName) ?: return false
                if (fileList.isEmpty()) {
                    result = copyAssetFile(srcName, dstName)
                } else {
                    val file = File(dstName)
                    result = file.mkdirs()
                    for (filename in fileList) {
                        result = result and copyAssetFolder(
                            srcName + separator.toString() + filename,
                            dstName + separator.toString() + filename
                        )
                    }
                }
                result
            } catch (e: IOException) {
                e.printStackTrace()
                false
            }
        }

        fun AssetManager.copyAssetFile(srcName: String, dstName: String): Boolean {
            return try {
                val inStream = this.open(srcName)
                val outFile = File(dstName)
                val out: OutputStream = FileOutputStream(outFile)
                val buffer = ByteArray(1024)
                var read: Int
                while (inStream.read(buffer).also { read = it } != -1) {
                    out.write(buffer, 0, read)
                }
                inStream.close()
                out.close()
                true
            } catch (e: IOException) {
                e.printStackTrace()
                false
            }
        }

    }
}