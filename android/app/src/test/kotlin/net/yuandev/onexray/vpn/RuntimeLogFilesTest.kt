package net.yuandev.onexray.vpn

import java.io.File
import java.io.IOException
import java.nio.file.Files
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Test

class RuntimeLogFilesTest {
    private lateinit var root: File

    @Before fun prepare() {
        val fixtures = File("../../../references/onexray-tests/android/runtime-logs").absoluteFile
        check(fixtures.mkdirs() || fixtures.isDirectory)
        root = Files.createTempDirectory(fixtures.toPath(), "logs-").toFile()
    }

    @After fun cleanup() { root.deleteRecursively() }

    @Test fun clearsOnlyManagedLogsAndAllowsMissingFiles() {
        val run = File(root, "run")
        RuntimeLogFiles.clear(run)
        check(run.mkdir())
        for (name in listOf("access.log", "error.log", "start.json", "export.log")) {
            File(run, name).writeText(name)
        }
        RuntimeLogFiles.clear(run)
        RuntimeLogFiles.clear(run)
        assertFalse(File(run, "access.log").exists())
        assertFalse(File(run, "error.log").exists())
        assertEquals("start.json", File(run, "start.json").readText())
        assertEquals("export.log", File(run, "export.log").readText())
    }

    @Test fun rejectsDirectoryLogBeforeClearingEither() {
        File(root, "access.log").writeText("old access")
        check(File(root, "error.log").mkdir())
        assertThrows(IOException::class.java) { RuntimeLogFiles.clear(root) }
        assertEquals("old access", File(root, "access.log").readText())
    }

    @Test fun rejectsLinkedLogAndRuntimeDirectory() {
        val access = File(root, "access.log").apply { writeText("old access") }
        val outside = File(root, "outside.log").apply { writeText("outside") }
        Files.createSymbolicLink(File(root, "error.log").toPath(), outside.toPath())
        assertThrows(IOException::class.java) { RuntimeLogFiles.clear(root) }
        assertEquals("old access", access.readText())
        assertEquals("outside", outside.readText())
        val linkedRun = File(root, "linked-run")
        Files.createSymbolicLink(linkedRun.toPath(), root.toPath())
        assertThrows(IOException::class.java) { RuntimeLogFiles.clear(linkedRun) }
        assertEquals("old access", access.readText())
    }
}
