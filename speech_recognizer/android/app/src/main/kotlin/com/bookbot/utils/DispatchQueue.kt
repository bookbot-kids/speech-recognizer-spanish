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