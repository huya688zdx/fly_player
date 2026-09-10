package com.geqian.flyplayer.fly_player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class SecureCredentialStoreTest {
    @Test
    fun readFailureKeepsEncryptedFileForRetry() {
        val file = Files.createTempFile("credential", ".json").toFile()
        file.writeText("encrypted-payload")

        val result = readCredentialFile(file) {
            throw IllegalStateException("temporary keystore failure")
        }

        assertEquals(CredentialReadStatus.ERROR, result.status)
        assertTrue(file.exists())
        file.delete()
    }

    @Test
    fun deleteFailureIsReported() {
        val file = Files.createTempFile("credential", ".json").toFile()

        val deleted = deleteCredentialFile(file) { false }

        assertFalse(deleted)
        assertTrue(file.exists())
        file.delete()
    }
}
