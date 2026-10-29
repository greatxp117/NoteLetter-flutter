package xp.NoteLetter.Flutter.camerasweep

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * When an Android change token can still answer (features/camera-roll-sweep.md
 * §7 rule 4, ADR-195). Every "no" is a walk of the whole library, which is
 * always right; a wrong "yes" would skip photos no pass ever reads.
 */
class LibraryHistoryTest {
    private val token = LibraryHistory.encode(mapOf(
        "external_primary" to ("v-a" to 120L),
        "1A2B-3C4D" to ("v-b" to 7L),
    ))

    @Test
    fun theSameVolumesAtTheSameVersionsReadFromTheirGenerations() {
        assertEquals(
            mapOf("external_primary" to 120L, "1A2B-3C4D" to 7L),
            LibraryHistory.generationsToRead(token, mapOf("external_primary" to "v-a", "1A2B-3C4D" to "v-b")),
        )
    }

    @Test
    fun aVolumeThatWentAwayNeedsNothing() {
        assertEquals(
            mapOf("external_primary" to 120L),
            LibraryHistory.generationsToRead(token, mapOf("external_primary" to "v-a")),
        )
    }

    @Test
    fun aRebuiltVolumeIsAWalk() {
        assertNull(LibraryHistory.generationsToRead(token, mapOf("external_primary" to "v-a2", "1A2B-3C4D" to "v-b")))
    }

    @Test
    fun aVolumeTheTokenNeverSawIsAWalk() {
        assertNull(LibraryHistory.generationsToRead(token,
            mapOf("external_primary" to "v-a", "1A2B-3C4D" to "v-b", "9F9F-0000" to "v-c")))
    }

    @Test
    fun anUnreadableTokenIsAWalk() {
        for (wire in listOf("", "not json", "[]", """{"external_primary": {"version": "v-a"}}""",
                """{"external_primary": {"version": "v-a", "generation": -1}}""")) {
            assertNull(wire, LibraryHistory.generationsToRead(wire, mapOf("external_primary" to "v-a")))
        }
    }
}
