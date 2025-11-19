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

import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

class DispatchQueue() {
    companion object {
        val recognitionQueue: ExecutorService = Executors.newSingleThreadExecutor {
            Thread(it, "recognizerQueue").apply {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_DEFAULT)
            }
        }

        val levelQueue: ExecutorService = Executors.newSingleThreadExecutor {
            Thread(it, "levelQueue").apply {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_DEFAULT)
            }
        }

        val recordingQueue: ExecutorService = Executors.newSingleThreadExecutor {
            Thread(it, "recordingQueue").apply {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_DEFAULT)
            }
        }

        val encodeQueue: ExecutorService = Executors.newSingleThreadExecutor {
            Thread(it, "encodeQueue").apply {
                android.os.Process.setThreadPriority(android.os.Process.THREAD_PRIORITY_DEFAULT)
            }
        }

        fun newQueue(size: Int, label: String, priority: Int = android.os.Process.THREAD_PRIORITY_DEFAULT): ExecutorService {
            return Executors.newFixedThreadPool(size) {
                Thread(it, label).apply {
                    android.os.Process.setThreadPriority(priority)
                }
            }
        }
    }
}