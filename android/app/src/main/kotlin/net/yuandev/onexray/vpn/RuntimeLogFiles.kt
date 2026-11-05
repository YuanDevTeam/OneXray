package net.yuandev.onexray.vpn

import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.LinkOption
import java.nio.file.NoSuchFileException
import java.nio.file.Path
import java.nio.file.attribute.BasicFileAttributes

/** Called only for an admitted new Core start, after the previous Core has stopped. */
internal object RuntimeLogFiles {
    fun clear(directory: File) {
        val root = directory.toPath()
        val rootAttributes = attributes(root) ?: return
        if (!rootAttributes.isDirectory) throw IOException("Invalid runtime log directory: $root")
        val files = listOf("access.log", "error.log").map { root.resolve(it) }.filter { path ->
            val attributes = attributes(path) ?: return@filter false
            if (!attributes.isRegularFile) throw IOException("Invalid runtime log file: $path")
            true
        }
        // Validate both before removing either, without enumerating the directory.
        files.forEach { Files.delete(it) }
    }

    private fun attributes(path: Path): BasicFileAttributes? = try {
        Files.readAttributes(path, BasicFileAttributes::class.java, LinkOption.NOFOLLOW_LINKS)
    } catch (_: NoSuchFileException) {
        null
    }
}
